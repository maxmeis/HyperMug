import Foundation
import CoreFoundation
import AppKit
import IOKit
import HyperMugCore

/// Runtime binding to MultitouchSupport. The ABI matches the pinned CMultitouch.h used by SwipeSwitcher.
private typealias Device = UnsafeMutableRawPointer
private typealias ContactCallback = @convention(c) (Device?, UnsafeRawPointer?, Int32, Double, Int32) -> Int32
private typealias CreateList = @convention(c) () -> Unmanaged<CFArray>?
private typealias Register = @convention(c) (Device?, ContactCallback) -> Void
private typealias Start = @convention(c) (Device?, Int32) -> Int32
private typealias Stop = @convention(c) (Device?) -> Int32
private typealias GetFamilyID = @convention(c) (Device?, UnsafeMutablePointer<Int32>?) -> Int32

final class TrackpadCapture {
    var onFrame: ((UInt64, [TrackpadContact], TimeInterval) -> Void)?
    var onDeviceRemoved: ((UInt64) -> Void)?
    private let log: LogSink
    private let lock = NSLock()
    private var library: UnsafeMutableRawPointer?
    private var createList: CreateList?
    private var register: Register?
    private var unregister: Register?
    private var startDevice: Start?
    private var stopDevice: Stop?
    private var getFamilyID: GetFamilyID?
    private var list: CFArray?
    private var devices: [UInt64: Device] = [:]
    private var generation: UInt64 = 0
    private var enabled = false
    private var port: IONotificationPortRef?
    private var added: io_iterator_t = 0
    private var removed: io_iterator_t = 0
    private var wakeObserver: NSObjectProtocol?

    init(log: @escaping LogSink) { self.log = log }

    func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        if on { load(); observe(); rescan() } else { stop(); unobserve() }
    }

    func shutdown() { enabled = false; stop(); unobserve() }

    private func load() {
        guard library == nil else { return }
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW) else {
            log(.info, "MultitouchSupport unavailable")
            return
        }
        func symbol<T>(_ name: String, as: T.Type) -> T? {
            guard let pointer = dlsym(handle, name) else { return nil }
            return unsafeBitCast(pointer, to: T.self)
        }
        guard let make: CreateList = symbol("MTDeviceCreateList", as: CreateList.self),
              let reg: Register = symbol("MTRegisterContactFrameCallback", as: Register.self),
              let unreg: Register = symbol("MTUnregisterContactFrameCallback", as: Register.self),
              let start: Start = symbol("MTDeviceStart", as: Start.self),
              let stop: Stop = symbol("MTDeviceStop", as: Stop.self) else {
            dlclose(handle)
            log(.error, "MultitouchSupport required symbols unavailable")
            return
        }
        library = handle; createList = make; register = reg; unregister = unreg
        startDevice = start; stopDevice = stop
        getFamilyID = symbol("MTDeviceGetFamilyID", as: GetFamilyID.self)
    }

    private func rescan() {
        guard enabled, let make = createList else { return }
        // Callback entries are detached before stopping; MTDeviceStop can wait for a callback.
        stop()
        guard let newList = make()?.takeRetainedValue() else { return }
        list = newList
        let count = CFArrayGetCount(newList)
        guard count > 0 else { return }
        lock.lock()
        generation &+= 1
        for index in 0..<count {
            let device = unsafeBitCast(CFArrayGetValueAtIndex(newList, index), to: Device.self)
            var family: Int32 = 0
            if getFamilyID?(device, &family) == 0 && (family == 112 || family == 113) { continue }
            devices[UInt64(UInt(bitPattern: device))] = device
        }
        let current = Array(devices.values)
        lock.unlock()
        for device in current {
            register?(device, trackpadContactCallback)
            let result = startDevice?(device, 0) ?? -1
            if result != 0 { log(.info, "trackpad device start returned \(result)") }
        }
    }

    private func stop() {
        lock.lock()
        generation &+= 1
        let old = devices
        devices.removeAll()
        lock.unlock()
        for (id, device) in old {
            unregister?(device, trackpadContactCallback)
            _ = stopDevice?(device)
            onDeviceRemoved?(id)
        }
        list = nil
    }

    fileprivate func receive(_ device: Device?, _ touches: UnsafeRawPointer?, _ count: Int32, _ timestamp: Double) {
        guard let device else { return }
        let id = UInt64(UInt(bitPattern: device))
        lock.lock()
        let valid = devices[id] != nil
        let epoch = generation
        lock.unlock()
        guard valid, count >= 0, count <= 32, count == 0 || touches != nil else { return }
        var contacts: [TrackpadContact] = []
        if let touches {
            for index in 0..<Int(count) {
                let base = touches.advanced(by: index * 96)
                func int32(_ offset: Int) -> Int32 { var v: Int32 = 0; memcpy(&v, base.advanced(by: offset), 4); return v }
                func float(_ offset: Int) -> Float { var v: Float = 0; memcpy(&v, base.advanced(by: offset), 4); return v }
                contacts.append(TrackpadContact(identifier: int32(16), state: int32(20),
                                                x: Double(float(32)), y: Double(float(36))))
            }
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let current = self.generation == epoch && self.devices[id] != nil
            self.lock.unlock()
            if current { self.onFrame?(id, contacts, timestamp) }
        }
    }

    private func observe() {
        guard port == nil else { return }
        guard let p = IONotificationPortCreate(kIOMainPortDefault) else { return }
        port = p
        IONotificationPortSetDispatchQueue(p, DispatchQueue.main)
        let ref = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOServiceMatchingCallback = { context, iterator in
            while case let service = IOIteratorNext(iterator), service != 0 { IOObjectRelease(service) }
            guard let context else { return }
            Unmanaged<TrackpadCapture>.fromOpaque(context).takeUnretainedValue().rescan()
        }
        if IOServiceAddMatchingNotification(p, kIOFirstMatchNotification,
                 IOServiceMatching("AppleMultitouchDevice"), callback, ref, &added) == KERN_SUCCESS {
            while case let service = IOIteratorNext(added), service != 0 { IOObjectRelease(service) }
        }
        if IOServiceAddMatchingNotification(p, kIOTerminatedNotification,
                 IOServiceMatching("AppleMultitouchDevice"), callback, ref, &removed) == KERN_SUCCESS {
            while case let service = IOIteratorNext(removed), service != 0 { IOObjectRelease(service) }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main) { [weak self] _ in self?.rescan() }
    }

    private func unobserve() {
        if added != 0 { IOObjectRelease(added); added = 0 }
        if removed != 0 { IOObjectRelease(removed); removed = 0 }
        if let port { IONotificationPortDestroy(port); self.port = nil }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver); self.wakeObserver = nil }
    }
}

private let trackpadContactCallback: ContactCallback = { device, touches, count, timestamp, _ in
    TrackpadCallbackRouter.shared.receive(device, touches, count, timestamp)
    return 0
}

/// The private callback has no context parameter. Keep only a weak host reference here.
final class TrackpadCallbackRouter {
    static let shared = TrackpadCallbackRouter()
    weak var host: TrackpadCapture?
    private init() {}
    fileprivate func receive(_ d: Device?, _ t: UnsafeRawPointer?, _ n: Int32, _ time: Double) {
        host?.receive(d, t, n, time)
    }
}

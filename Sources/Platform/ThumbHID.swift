import Foundation
import HyperMugCore
import IOKit
import IOKit.hid

// MARK: - IOHIDManager adapter for the thumb button
//
// All decisions live in Core's `ThumbController`; this class only owns the OS objects. It feeds device events
// and results in, and executes the returned commands in order. Everything runs on the main run loop.
// Discovery needs no permission; opening a device (needed to send/receive HID++) needs Input Monitoring.

private let logitechVendorID = 0x046D
private let hidppUsagePage = 0xFF43
private let hidppUsage = 0x0202
private let inputBufferSize = 64

private func intProperty(_ device: IOHIDDevice, _ key: String) -> Int? {
    IOHIDDeviceGetProperty(device, key as CFString) as? Int
}

private func stringProperty(_ device: IOHIDDevice, _ key: String) -> String? {
    IOHIDDeviceGetProperty(device, key as CFString) as? String
}

/// The device identity Core uses: the IORegistry entry ID, stable for as long as the device is attached.
private func registryID(_ device: IOHIDDevice) -> HIDDeviceID? {
    var id: UInt64 = 0
    guard IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &id) == KERN_SUCCESS else { return nil }
    return id
}

private final class ThumbDevice {
    let id: HIDDeviceID
    let device: IOHIDDevice
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: inputBufferSize)
    weak var owner: ThumbHID?

    init(id: HIDDeviceID, device: IOHIDDevice, owner: ThumbHID) {
        self.id = id
        self.device = device
        self.owner = owner
        buffer.initialize(repeating: 0, count: inputBufferSize)
    }

    deinit { buffer.deallocate() }
}

// C callbacks: no captures. Contexts are unretained pointers to objects that outlive the registration.

private func deviceMatchedCallback(context: UnsafeMutableRawPointer?, result: IOReturn,
                                   sender: UnsafeMutableRawPointer?, device: IOHIDDevice) {
    guard let context, let id = registryID(device) else { return }
    Unmanaged<ThumbHID>.fromOpaque(context).takeUnretainedValue().deviceMatched(device, id: id)
}

private func deviceRemovedCallback(context: UnsafeMutableRawPointer?, result: IOReturn,
                                   sender: UnsafeMutableRawPointer?, device: IOHIDDevice) {
    guard let context, let id = registryID(device) else { return }
    Unmanaged<ThumbHID>.fromOpaque(context).takeUnretainedValue().deviceRemoved(id: id)
}

private func inputReportCallback(context: UnsafeMutableRawPointer?, result: IOReturn, sender: UnsafeMutableRawPointer?,
                                 type: IOHIDReportType, reportID: UInt32,
                                 report: UnsafeMutablePointer<UInt8>, length: CFIndex) {
    // Mouse reports (ID 0x02) arrive here at 100+ Hz; reject them before allocating anything.
    guard length > 0, HIDPP.isCandidateReport(reportID: reportID, length: length, firstByte: report[0]),
          let context else { return }
    let device = Unmanaged<ThumbDevice>.fromOpaque(context).takeUnretainedValue()
    device.owner?.received(device.id, reportID: reportID, bytes: Array(UnsafeBufferPointer(start: report, count: length)))
}

final class ThumbHID {
    var onPress: (() -> Void)?                        // main thread, once per press

    private var core = ThumbController()
    private let log: LogSink
    private var manager: IOHIDManager?
    private var devices: [HIDDeviceID: ThumbDevice] = [:]

    init(log: @escaping LogSink) {
        self.log = log
    }

    // MARK: Lifecycle

    /// Creates the manager and starts device discovery. Does not open any device.
    func start() {
        guard manager == nil else { return }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Int] = [
            kIOHIDVendorIDKey: logitechVendorID,
            kIOHIDDeviceUsagePageKey: hidppUsagePage,
            kIOHIDDeviceUsageKey: hidppUsage,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, deviceMatchedCallback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, deviceRemovedCallback, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        self.manager = manager
        log(.info, "HID++ discovery started")
    }

    /// true: divert the thumb button on every matched mouse. false: undivert and close.
    func setEnabled(_ on: Bool) {
        run(core.setEnabled(on, access: inputMonitoringAccess(), now: now()))
    }

    /// Called from the 2 s timer: request retries/timeouts and permission re-check.
    func tick() {
        run(core.tick(access: inputMonitoringAccess(), now: now()))
    }

    /// Synchronously undivert and close everything. Safe to call twice.
    func shutdown() {
        run(core.shutdown())
        devices.removeAll()
        guard let manager else { return }
        IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        self.manager = nil
    }

    // MARK: Events from the callbacks (main run loop)

    fileprivate func deviceMatched(_ device: IOHIDDevice, id: HIDDeviceID) {
        devices[id] = devices[id] ?? ThumbDevice(id: id, device: device, owner: self)
        let info = ThumbDeviceInfo(name: stringProperty(device, kIOHIDProductKey),
                                   transport: stringProperty(device, kIOHIDTransportKey),
                                   productID: intProperty(device, kIOHIDProductIDKey),
                                   primaryUsagePage: intProperty(device, kIOHIDPrimaryUsagePageKey),
                                   primaryUsage: intProperty(device, kIOHIDPrimaryUsageKey))
        run(core.deviceMatched(id, info, access: inputMonitoringAccess(), now: now()))
    }

    fileprivate func deviceRemoved(id: HIDDeviceID) {
        run(core.deviceRemoved(id))
        devices[id] = nil
    }

    fileprivate func received(_ id: HIDDeviceID, reportID: UInt32, bytes: [UInt8]) {
        run(core.received(id, reportID: reportID, bytes: bytes, now: now()))
    }

    // MARK: Command execution

    private func now() -> Double {
        ProcessInfo.processInfo.systemUptime
    }

    private func run(_ commands: [ThumbCommand]) {
        for command in commands {
            switch command {
            case let .open(id):
                open(id)
            case let .write(id, payloads):
                write(id, payloads)
            case let .close(id):
                close(id)
            case .requestAccess:
                requestInputMonitoringAccess { [weak self] granted in
                    guard let self else { return }
                    self.run(self.core.accessRequestFinished(granted: granted, now: self.now()))
                }
            case .press:
                onPress?()
            case let .log(level, message):
                log(level, message)
            }
        }
    }

    private func open(_ id: HIDDeviceID) {
        guard let thumbDevice = devices[id] else { return }
        let result = IOHIDDeviceOpen(thumbDevice.device, IOOptionBits(kIOHIDOptionsTypeNone))   // non-seize: the mouse keeps working
        if result == kIOReturnSuccess {
            IOHIDDeviceRegisterInputReportCallback(thumbDevice.device, thumbDevice.buffer, inputBufferSize, inputReportCallback,
                                                   Unmanaged.passUnretained(thumbDevice).toOpaque())
            IOHIDDeviceScheduleWithRunLoop(thumbDevice.device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        }
        run(core.openFinished(id, code: UInt32(bitPattern: result), now: now()))
    }

    /// SetReport for each payload until one is accepted; Core decides the order and learns which one worked.
    private func write(_ id: HIDDeviceID, _ payloads: [[UInt8]]) {
        guard let thumbDevice = devices[id] else { return }
        var succeededIndex: Int?
        var lastResult = kIOReturnSuccess
        for (index, payload) in payloads.enumerated() {
            lastResult = payload.withUnsafeBufferPointer {
                IOHIDDeviceSetReport(thumbDevice.device, kIOHIDReportTypeOutput, CFIndex(HIDPP.reportID), $0.baseAddress!, $0.count)
            }
            if lastResult == kIOReturnSuccess {
                succeededIndex = index
                break
            }
        }
        run(core.writeFinished(id, succeededIndex: succeededIndex, lastCode: UInt32(bitPattern: lastResult)))
    }

    private func close(_ id: HIDDeviceID) {
        guard let thumbDevice = devices[id] else { return }
        IOHIDDeviceRegisterInputReportCallback(thumbDevice.device, thumbDevice.buffer, inputBufferSize, nil, nil)
        IOHIDDeviceUnscheduleFromRunLoop(thumbDevice.device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDDeviceClose(thumbDevice.device, IOOptionBits(kIOHIDOptionsTypeNone))
    }
}

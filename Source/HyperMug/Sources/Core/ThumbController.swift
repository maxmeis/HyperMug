import Foundation

// MARK: - Thumb button session logic (pure; the IOHIDManager adapter lives in Platform/ThumbHID.swift)
//
// The thumb button is CID 0x00C3 of feature 0x1B04 (REPROG_CONTROLS_V4). Diverting it makes the mouse stop
// sending its native HID action and report presses as HID++ events instead.
//
// `ThumbController` owns every decision: which devices count, when to open them, the request/reply state machine
// (feature lookup → divert → events → undivert), retries and the permission policy. It never touches a device:
// each call returns `ThumbCommand`s that the adapter executes in order. The adapter reports what happened
// through `openFinished`, `writeFinished` and `accessRequestFinished`; `now` is a monotonic clock in seconds.

public typealias HIDDeviceID = UInt64

public struct ThumbDeviceInfo: Equatable {
    public var name: String?
    public var transport: String?
    public var productID: Int?
    public var primaryUsagePage: Int?
    public var primaryUsage: Int?

    public init(name: String? = nil, transport: String? = nil, productID: Int? = nil,
                primaryUsagePage: Int? = nil, primaryUsage: Int? = nil) {
        self.name = name
        self.transport = transport
        self.productID = productID
        self.primaryUsagePage = primaryUsagePage
        self.primaryUsage = primaryUsage
    }
}

public enum ThumbCommand: Equatable {
    case open(HIDDeviceID)                           // adapter: IOHIDDeviceOpen (+register/schedule on success), then openFinished
    case write(HIDDeviceID, payloads: [[UInt8]])     // adapter: SetReport each until one succeeds, then writeFinished
    case close(HIDDeviceID)                          // adapter: unregister, unschedule, IOHIDDeviceClose
    case requestAccess                               // adapter: IOHIDRequestAccess off-main, then accessRequestFinished on main
    case press                                       // the thumb button was pressed
    case log(LogLevel, String)
}

private let thumbRequestTimeout = 1.5
private let thumbMaxSendAttempts = 3
private let thumbNotPermittedCode: UInt32 = 0xE00002E2      // kIOReturnNotPermitted

private func thumbHex(_ value: Int) -> String { String(format: "0x%04X", value) }
private func thumbHexIO(_ value: UInt32) -> String { String(format: "0x%08X", value) }

private let thumbDeniedText =
    "Input Monitoring denied — enable \(AppIdentity.appName) in System Settings › Privacy & Security › Input Monitoring"

private enum ThumbStage: Equatable {
    case lookupReprog    // waiting for IRoot.getFeature(0x1B04)
    case lookupWds       // waiting for IRoot.getFeature(0x1D4B)
    case diverting       // waiting for the setCidReporting(divert) reply
}

private struct ThumbPending: Equatable {
    let stage: ThumbStage
    let featureIndex: UInt8
    let function: UInt8
    let bytes: [UInt8]
    var sentAt: Double
    var attempts: Int
}

private enum ThumbState: Equatable {
    case closed              // not open; opened when enabled and permitted
    case awaiting(ThumbPending)   // open, one request in flight
    case diverted            // open, events flow
    case unsupported         // feature or CID absent; left alone until re-enabled or reconnected
    case failed              // no replies; left alone until re-enabled or reconnected
}

private struct ThumbSession {
    let id: HIDDeviceID
    let name: String
    var state = ThumbState.closed
    var reprogIndex: UInt8 = 0
    var wdsIndex: UInt8 = 0
    var pressed: [UInt16] = []
    var sendReportID = true          // SetReport payload includes the 0x11 ID byte (hidapi convention); flips if rejected
    var lastOpenCode: UInt32 = 0

    init(id: HIDDeviceID, name: String) {
        self.id = id
        self.name = name
    }

    /// The device is open exactly while a request is in flight or events flow.
    var isOpen: Bool {
        switch state {
        case .awaiting, .diverted: return true
        case .closed, .unsupported, .failed: return false
        }
    }

    /// Button events count once the divert request is out, even before its echo arrives.
    var acceptsButtonEvents: Bool {
        switch state {
        case .diverted: return true
        case let .awaiting(pending): return pending.stage == .diverting
        case .closed, .unsupported, .failed: return false
        }
    }
}

public struct ThumbController {
    public private(set) var enabled = false
    private var sessions: [ThumbSession] = []
    private var accessRequested = false
    private var accessRequestInFlight = false
    private var deniedLogged = false

    public init() {}

    // MARK: Discovery

    /// A device matched the HID++ vendor interface. Only mice are accepted: CID 0x00C3 is a different key
    /// (context menu) on Logitech keyboards.
    public mutating func deviceMatched(_ id: HIDDeviceID, _ info: ThumbDeviceInfo, access: HIDAccess,
                                       now: Double) -> [ThumbCommand] {
        let name = info.name ?? "unknown device"
        guard info.primaryUsagePage == 0x01, info.primaryUsage == 0x02 else {
            return [.log(.info, "skipped \(name): not a mouse (primary usage \(info.primaryUsagePage ?? -1):\(info.primaryUsage ?? -1))")]
        }
        guard index(of: id) == nil else { return [] }
        var out: [ThumbCommand] = [
            .log(.info, "matched \(name) (PID \(thumbHex(info.productID ?? 0)), transport \(info.transport ?? "unknown"))"),
        ]
        sessions.append(ThumbSession(id: id, name: name))
        if enabled { out += open(at: sessions.count - 1, access: access) }
        return out
    }

    /// The device went away (BLE disconnect): drop the session without any I/O.
    public mutating func deviceRemoved(_ id: HIDDeviceID) -> [ThumbCommand] {
        guard let i = index(of: id) else { return [] }
        var session = sessions.remove(at: i)
        return [.log(.info, "removed \(session.name); dropping session")]
            + Self.close(&session, undivert: false, finalState: .closed)
    }

    // MARK: Lifecycle

    /// true: divert the thumb button on every matched mouse. false: undivert and close.
    public mutating func setEnabled(_ on: Bool, access: HIDAccess, now: Double) -> [ThumbCommand] {
        guard on != enabled else { return [] }
        enabled = on
        guard on else { return closeAll() }
        var out: [ThumbCommand] = []
        for i in sessions.indices { out += open(at: i, access: access) }
        return out
    }

    /// Called from the 2 s timer: open retries, request timeouts and the permission re-check.
    public mutating func tick(access: HIDAccess, now: Double) -> [ThumbCommand] {
        guard enabled else { return [] }
        var out: [ThumbCommand] = []
        for i in sessions.indices {
            switch sessions[i].state {
            case .closed:
                out += open(at: i, access: access)
            case let .awaiting(pending):
                out += Self.retry(&sessions[i], pending, now: now)
            case .diverted, .unsupported, .failed:
                break
            }
        }
        return out
    }

    /// Undivert and close everything and forget all sessions. Safe to call twice.
    public mutating func shutdown() -> [ThumbCommand] {
        enabled = false
        let out = closeAll()
        sessions.removeAll()
        return out
    }

    // MARK: Adapter results

    /// Result of `.open`. Success starts the feature lookup; a failure is logged once per distinct code.
    public mutating func openFinished(_ id: HIDDeviceID, code: UInt32, now: Double) -> [ThumbCommand] {
        guard let i = index(of: id) else { return [] }
        let name = sessions[i].name
        guard code == 0 else {
            guard code != sessions[i].lastOpenCode else { return [] }
            sessions[i].lastOpenCode = code
            if code == thumbNotPermittedCode {
                return [.log(.error, "opening \(name) not permitted (\(thumbHexIO(code))); relaunch \(AppIdentity.appName) after granting Input Monitoring")]
            }
            return [.log(.error, "opening \(name) failed (\(thumbHexIO(code)))")]
        }
        sessions[i].lastOpenCode = 0
        let opened = ThumbCommand.log(.info, "opened \(name); looking up feature \(thumbHex(Int(HIDPP.reprogControlsV4)))")
        return [opened, Self.lookup(&sessions[i], stage: .lookupReprog, feature: HIDPP.reprogControlsV4, now: now)]
    }

    /// Result of `.write`: the index of the payload that succeeded (nil: all failed, `lastCode` is the last error).
    /// May arrive for a session that was just closed or dropped; it then only logs.
    public mutating func writeFinished(_ id: HIDDeviceID, succeededIndex: Int?, lastCode: UInt32) -> [ThumbCommand] {
        let i = index(of: id)
        guard let succeeded = succeededIndex else {
            let name = i.map { sessions[$0].name } ?? "device"
            return [.log(.error, "SetReport to \(name) failed (\(thumbHexIO(lastCode)))")]
        }
        // Payloads are ordered preferred-first, so the second one working flips the preference.
        if succeeded == 1, let i { sessions[i].sendReportID.toggle() }
        return []
    }

    /// Result of `.requestAccess`.
    public mutating func accessRequestFinished(granted: Bool, now: Double) -> [ThumbCommand] {
        accessRequestInFlight = false
        guard granted else { return denied() }
        var out: [ThumbCommand] = [.log(.info, "Input Monitoring granted")]
        guard enabled else { return out }
        for i in sessions.indices { out += open(at: i, access: .granted) }
        return out
    }

    // MARK: Input

    /// One input report from an open device. Mouse reports and foreign HID++ traffic are dropped.
    public mutating func received(_ id: HIDDeviceID, reportID: UInt32, bytes: [UInt8], now: Double) -> [ThumbCommand] {
        guard let message = HIDPP.parse(reportID: reportID, bytes: bytes), let i = index(of: id) else { return [] }
        return Self.handle(message, &sessions[i], now: now)
    }

    // MARK: Permission

    private func index(of id: HIDDeviceID) -> Int? {
        sessions.firstIndex { $0.id == id }
    }

    private mutating func denied() -> [ThumbCommand] {
        guard !deniedLogged else { return [] }
        deniedLogged = true
        return [.log(.error, thumbDeniedText)]
    }

    /// Input Monitoring is required to open the device. Requests it at most once per launch (the system prompt).
    private mutating func permitted(_ access: HIDAccess, _ out: inout [ThumbCommand]) -> Bool {
        if access == .granted {
            deniedLogged = false
            return true
        }
        if !accessRequested {
            accessRequested = true
            accessRequestInFlight = true
            out.append(.log(.info, "Input Monitoring is \(access == .denied ? "denied" : "unknown"); requesting access"))
            out.append(.requestAccess)
        } else if !accessRequestInFlight {
            out += denied()
        }
        return false
    }

    // MARK: Session control

    private mutating func open(at i: Int, access: HIDAccess) -> [ThumbCommand] {
        guard sessions[i].state == .closed else { return [] }
        var out: [ThumbCommand] = []
        guard permitted(access, &out) else { return out }
        return [.open(sessions[i].id)]
    }

    private mutating func closeAll() -> [ThumbCommand] {
        var out: [ThumbCommand] = []
        for i in sessions.indices { out += Self.close(&sessions[i], undivert: true, finalState: .closed) }
        return out
    }

    /// Optionally undivert (best effort), then release the device. `finalState` is what the session reports afterwards.
    /// The session is reset before the commands are returned, so late results for it are harmless.
    private static func close(_ s: inout ThumbSession, undivert: Bool, finalState: ThumbState) -> [ThumbCommand] {
        var out: [ThumbCommand] = []
        if s.isOpen {
            if undivert && s.reprogIndex != 0 {
                let bytes = HIDPP.setCidReporting(featureIndex: s.reprogIndex, cid: HIDPP.thumbCID, divert: false)
                out.append(.log(.info, "undiverting CID \(thumbHex(Int(HIDPP.thumbCID))) on \(s.name)"))
                out.append(.write(s.id, payloads: payloads(s, bytes)))
            }
            out.append(.close(s.id))
        }
        s.state = finalState
        s.reprogIndex = 0
        s.wdsIndex = 0
        s.pressed = []
        return out
    }

    // MARK: Requests

    /// With the report ID byte first (hidapi convention) and without it; the one that worked last goes first.
    private static func payloads(_ s: ThumbSession, _ bytes: [UInt8]) -> [[UInt8]] {
        let withoutID = Array(bytes.dropFirst())
        return s.sendReportID ? [bytes, withoutID] : [withoutID, bytes]
    }

    private static func send(_ s: inout ThumbSession, stage: ThumbStage, featureIndex: UInt8, function: UInt8,
                             bytes: [UInt8], now: Double) -> ThumbCommand {
        s.state = .awaiting(ThumbPending(stage: stage, featureIndex: featureIndex, function: function, bytes: bytes,
                                    sentAt: now, attempts: 1))
        return .write(s.id, payloads: payloads(s, bytes))
    }

    private static func lookup(_ s: inout ThumbSession, stage: ThumbStage, feature: UInt16, now: Double) -> ThumbCommand {
        send(&s, stage: stage, featureIndex: 0, function: 0, bytes: HIDPP.getFeature(feature), now: now)
    }

    private static func divert(_ s: inout ThumbSession, now: Double) -> ThumbCommand {
        let index = s.reprogIndex
        let bytes = HIDPP.setCidReporting(featureIndex: index, cid: HIDPP.thumbCID, divert: true)
        return send(&s, stage: .diverting, featureIndex: index, function: 3, bytes: bytes, now: now)
    }

    /// Resend a request that got no reply within the timeout; give up after the attempt budget.
    private static func retry(_ s: inout ThumbSession, _ pending: ThumbPending, now: Double) -> [ThumbCommand] {
        guard now - pending.sentAt > thumbRequestTimeout else { return [] }
        let name = s.name
        guard pending.attempts < thumbMaxSendAttempts else {
            let gaveUp = ThumbCommand.log(.error,
                "no HID++ reply from \(name) after \(pending.attempts) attempts; giving up until reconnect or re-enable")
            return [gaveUp] + close(&s, undivert: true, finalState: .failed)
        }
        var next = pending
        next.attempts += 1
        next.sentAt = now
        s.state = .awaiting(next)
        return [.log(.info, "resending HID++ request to \(name) (attempt \(next.attempts))"),
                .write(s.id, payloads: payloads(s, pending.bytes))]
    }

    // MARK: Incoming messages

    private static func matchingPending(_ s: ThumbSession, featureIndex: UInt8, function: UInt8) -> ThumbPending? {
        guard case let .awaiting(pending) = s.state, pending.featureIndex == featureIndex,
              pending.function == function else { return nil }
        return pending
    }

    private static func handle(_ message: HIDPP.Message, _ s: inout ThumbSession, now: Double) -> [ThumbCommand] {
        switch message {
        case let .response(featureIndex, function, params):
            guard let pending = matchingPending(s, featureIndex: featureIndex, function: function) else { return [] }
            // A retried getFeature(0x1B04) can produce a late duplicate reply; it must not answer the 0x1D4B lookup.
            if pending.stage == .lookupWds && HIDPP.isDuplicateLookupReply(params, knownIndex: s.reprogIndex) { return [] }
            return advance(&s, from: pending.stage, reply: params[0], now: now)

        case let .error(featureIndex, function, code):
            guard let pending = matchingPending(s, featureIndex: featureIndex, function: function) else { return [] }
            let failure = ThumbCommand.log(.error,
                "HID++ error 0x\(String(code, radix: 16)) from \(s.name) (feature index \(featureIndex), function \(function))")
            return [failure] + recover(&s, from: pending.stage, now: now)

        case let .event(featureIndex, function, params):
            guard function == 0 else { return [] }
            if featureIndex == s.reprogIndex && s.acceptsButtonEvents {
                let current = HIDPP.divertedCIDs(params)
                let pressed = thumbPressed(previous: s.pressed, current: current)
                s.pressed = current
                return pressed ? [.press] : []
            }
            // The device asks software to re-apply its configuration (e.g. after waking up).
            guard s.state == .diverted, s.wdsIndex != 0, featureIndex == s.wdsIndex,
                  HIDPP.isReconfigurationRequest(params) else { return [] }
            let again = ThumbCommand.log(.info, "\(s.name) asked for reconfiguration; diverting again")
            return [again, divert(&s, now: now)]
        }
    }

    /// The reply to the request of `stage` arrived; `index` is its first parameter byte.
    private static func advance(_ s: inout ThumbSession, from stage: ThumbStage, reply index: UInt8, now: Double) -> [ThumbCommand] {
        let name = s.name
        switch stage {
        case .lookupReprog:
            guard index != 0 else {
                let missing = ThumbCommand.log(.error,
                    "\(name) has no feature \(thumbHex(Int(HIDPP.reprogControlsV4))); thumb button unsupported")
                return [missing] + close(&s, undivert: false, finalState: .unsupported)
            }
            s.reprogIndex = index
            let found = ThumbCommand.log(.info, "\(name): \(thumbHex(Int(HIDPP.reprogControlsV4))) @ index \(index)")
            return [found, lookup(&s, stage: .lookupWds, feature: HIDPP.wirelessDeviceStatus, now: now)]

        case .lookupWds:
            s.wdsIndex = index
            var out: [ThumbCommand] = []
            if index != 0 {
                out.append(.log(.info, "\(name): \(thumbHex(Int(HIDPP.wirelessDeviceStatus))) @ index \(index)"))
            }
            out.append(divert(&s, now: now))
            return out

        case .diverting:
            s.state = .diverted
            return [.log(.info,
                "diverted CID \(thumbHex(Int(HIDPP.thumbCID))) on \(name) (\(thumbHex(Int(HIDPP.reprogControlsV4))) @ index \(s.reprogIndex))")]
        }
    }

    /// The request of `stage` was answered with an error.
    private static func recover(_ s: inout ThumbSession, from stage: ThumbStage, now: Double) -> [ThumbCommand] {
        switch stage {
        case .lookupReprog:
            return close(&s, undivert: false, finalState: .failed)
        case .lookupWds:
            s.wdsIndex = 0     // the wake-up notification is optional; divert anyway
            return [divert(&s, now: now)]
        case .diverting:
            let rejected = ThumbCommand.log(.error,
                "\(s.name) rejected diverting CID \(thumbHex(Int(HIDPP.thumbCID))); thumb button unsupported")
            return [rejected] + close(&s, undivert: false, finalState: .unsupported)
        }
    }
}

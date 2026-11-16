import Foundation

public enum CapsMonitorCommand: Equatable { case none, open, close }

/// Decides when the Caps Lock HID monitor opens or closes, and when an open result is worth a log line.
public struct CapsMonitorPolicy {
    private var attempted = false
    private var lastOpenResult: Int32?

    public init() {}

    /// Idempotent; called on every engine sync. After a failed open it retries only once Input Monitoring is granted.
    public mutating func setEnabled(_ on: Bool, isOpen: Bool, access: HIDAccess) -> CapsMonitorCommand {
        if on {
            if isOpen || (attempted && access != .granted) { return .none }
            attempted = true
            return .open
        }
        guard isOpen else { return .none }
        lastOpenResult = nil
        return .close
    }

    /// Debug line for an `IOHIDManagerOpen` result, only when it differs from the previous one.
    public mutating func openFinished(code: Int32) -> String? {
        guard code != lastOpenResult else { return nil }
        lastOpenResult = code
        return "caps hid open ok=\(code == 0) result=\(String(UInt32(bitPattern: code), radix: 16))"
    }
}

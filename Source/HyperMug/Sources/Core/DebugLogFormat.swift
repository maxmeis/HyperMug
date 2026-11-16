import Foundation

/// Keeps the debug log file below `maxBytes`: when the next line would not fit, the file is truncated first.
public struct DebugLogBudget {
    private let maxBytes: Int
    private var used = 0

    public init(maxBytes: Int = 1_000_000) {
        self.maxBytes = maxBytes
    }

    /// Call before appending a line of `byteCount` bytes. `true` = truncate the file first.
    public mutating func admit(byteCount: Int) -> Bool {
        let truncate = used + byteCount > maxBytes
        if truncate { used = 0 }
        used += byteCount
        return truncate
    }

    /// The file was emptied (app start).
    public mutating func reset() {
        used = 0
    }
}

/// `HH:mm:ss.SSS <text>` plus newline. Never log keycodes or characters of typed keys.
public func debugLogLine(_ text: String, timestamp: String) -> String {
    "\(timestamp) \(text)\n"
}

import Foundation

public enum LogLevel: Equatable { case info, error }

/// Where Core sends diagnostics. The app wires it to `os.Logger`; tests capture the lines.
public typealias LogSink = (LogLevel, String) -> Void

/// Handle for a scheduled job or a file watch; `cancel()` is idempotent.
public protocol Cancellable: AnyObject { func cancel() }

/// Input Monitoring state as Core sees it, translated from `IOHIDAccessType` by Platform.
public enum HIDAccess: Equatable { case granted, denied, unknown }

/// Single source for every name that identifies the app on disk, in the log and in the system.
public enum AppIdentity {
    #if HYPERMUG_DEV
    public static let isDevelopment = true
    public static let appName = "HyperMug Dev"
    public static let bundleID = "com.maxmeis.hypermug.dev"
    public static let configFileName = "hypermug-dev.toml"
    public static let legacyConfigFileName = "hypermug-dev.json"
    public static let schemaFileName = "hypermug-dev.schema.json"
    #else
    public static let isDevelopment = false
    public static let appName = "HyperMug"
    public static let bundleID = "com.maxmeis.hypermug"
    public static let configFileName = "hypermug.toml"            // in ~/.config
    public static let legacyConfigFileName = "hypermug.json"      // retired; its presence is only reported
    public static let schemaFileName = "hypermug.schema.json"
    #endif
    public static let logSubsystem = bundleID
    public static let debugLogDirectory = "Library/Logs/\(appName)"
    public static let caffeineAssertionName = "\(appName) Caffeine"
}

/// One-at-a-time gate for modal UI (the privileges alert).
public struct ModalGate {
    private var open = false

    public init() {}

    /// True if the caller may show its modal now; false while another one is up.
    public mutating func tryEnter() -> Bool {
        if open { return false }
        open = true
        return true
    }

    public mutating func leave() {
        open = false
    }
}

/// One alert at a time; while one is showing, only the latest arrival is remembered.
public struct AlertQueue<Item: Equatable> {
    private var showing = false
    private var pending: Item?

    public init() {}

    /// Non-nil: show this item now. Nil: an alert is up, the item is remembered instead.
    public mutating func arrive(_ item: Item) -> Item? {
        if showing {
            pending = item
            return nil
        }
        showing = true
        return item
    }

    /// Call when the alert closed. Returns the remembered item only if it still equals `stillCurrent`
    /// (e.g. the store's current error); the caller shows it next, and the queue counts it as showing.
    public mutating func dismissed(stillCurrent: Item?) -> Item? {
        showing = false
        let next = pending
        pending = nil
        guard let next, next == stillCurrent else { return nil }
        showing = true
        return next
    }
}

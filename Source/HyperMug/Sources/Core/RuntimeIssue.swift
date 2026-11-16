import Foundation

/// Native error feedback contains status, never a command, environment or shell output.
public enum RuntimeIssue: Equatable, Sendable {
    case configuration
    case shellStart(Int32)
    case shellExit(Int32)
    case shellTimeout(Double)
    case shellBusy
    case shortcut

    public var identifier: String {
        switch self {
        case .configuration: return "configuration"
        case .shellStart: return "shell-start"
        case .shellExit: return "shell-exit"
        case .shellTimeout: return "shell-timeout"
        case .shellBusy: return "shell-busy"
        case .shortcut: return "shortcut"
        }
    }

    public var title: String {
        switch self {
        case .configuration: return "Configuration could not be loaded"
        case .shellTimeout: return "Shell action timed out"
        default: return "Action could not complete"
        }
    }

    public var body: String {
        switch self {
        case .configuration:
            return "Check the configuration file. The last valid settings remain active."
        case .shellStart(let code):
            return "A shell action could not start (system error \(code)). Check the configuration and Doctor activity."
        case .shellExit(let code):
            return "A shell action failed (exit status \(code)). Check the configuration and Doctor activity."
        case .shellTimeout(let seconds):
            return "A shell action exceeded \(seconds.formatted()) seconds and was stopped. Check shellTimeoutSeconds in the configuration."
        case .shellBusy:
            return "Too many shell actions are still running. Wait for them to finish or reach their time limit."
        case .shortcut:
            return "The keyboard shortcut could not be created. Check input permissions in Doctor."
        }
    }
}

/// A small finite set of issue categories prevents repeated swipes from flooding Notification Center.
public struct IssueNotificationGate {
    private var last: [String: TimeInterval] = [:]
    public init() {}

    public mutating func admit(_ issue: RuntimeIssue, now: TimeInterval) -> Bool {
        if let previous = last[issue.identifier], now - previous < 30 { return false }
        last[issue.identifier] = now
        return true
    }

    public mutating func configurationRecovered() { last.removeValue(forKey: "configuration") }
}

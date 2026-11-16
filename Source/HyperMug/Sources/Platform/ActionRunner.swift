import Foundation
import CoreGraphics
import HyperMugCore

/// Runs a configured button action. Call on the main thread; never blocks.
enum ActionRunner {
    private static let log = makeLogSink(category: "actions")

    static func run(_ action: ButtonAction) {
        switch action {
        case .shortcut(let shortcut): post(keyCode: shortcut.keyCode, flags: postedFlags(for: shortcut))
        case .shell(let command): runShell(command)
        case .helper: reportAsync(.configuration)
        }
    }

    static func postEscape() {
        post(keyCode: escapeKeyCode, flags: [])
    }

    // MARK: Keys

    /// Posts key down + up tagged with `kSyntheticEventTag`, so the tap lets them through untouched.
    private static func post(keyCode: CGKeyCode, flags: CGEventFlags) {
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: down) else {
                reportAsync(.shortcut)
                return
            }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: kSyntheticEventTag)
            event.post(tap: .cghidEventTap)
        }
    }

    // MARK: Shell

    @MainActor static var onIssue: ((RuntimeIssue) -> Void)?
    @MainActor private static let executor = ShellExecutor()
    @MainActor private static var timeout: TimeInterval = 10

    @MainActor static func configure(timeout seconds: TimeInterval) { timeout = seconds }
    @MainActor static func shutdown() { executor.shutdown() }

    private static func runShell(_ command: String) {
        Task { @MainActor in
            let identifier = UUID().uuidString
            DebugLog.write("Shell action started id=\(identifier)")
            executor.run(command, timeout: timeout) { issue in report(issue, identifier: identifier) }
        }
    }

    private static func reportAsync(_ issue: RuntimeIssue) {
        Task { @MainActor in report(issue) }
    }

    @MainActor private static func report(_ issue: RuntimeIssue, identifier: String? = nil) {
        let detail = identifier.map { issue.body + " [action \($0)]" } ?? issue.body
        log(.error, detail)
        DebugLog.write(detail)
        onIssue?(issue)
    }
}

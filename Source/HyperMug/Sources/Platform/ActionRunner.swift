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
        case .helper(let name): log(.error, "unresolved helper: \(name)")
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
                log(.error, "could not create key event")
                return
            }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: kSyntheticEventTag)
            event.post(tap: .cghidEventTap)
        }
    }

    // MARK: Shell

    private static func runShell(_ command: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                DebugLog.write("shell action exited status=\(process.terminationStatus)")
                if process.terminationStatus != 0 {
                    log(.info, "shell command exited with status \(process.terminationStatus): \(command)")
                }
            } catch {
                DebugLog.write("shell action failed to start: \(error.localizedDescription)")
                log(.error, "shell command failed to start: \(error.localizedDescription)")
            }
        }
    }
}

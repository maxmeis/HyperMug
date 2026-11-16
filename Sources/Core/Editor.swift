import Foundation

// Pure decisions for "Settings…": resolve the user's `$EDITOR` from their login shell, decide whether to
// run it or fall back to the default app, and gate repeated requests. All process and workspace work
// lives in Platform/EditorLauncher.swift.

/// First words of `$EDITOR` that need a terminal; those are not run from a GUI app.
public let terminalEditors: Set<String> = [
    "vi", "vim", "nvim", "nano", "emacs", "micro", "hx", "helix", "kak", "joe", "ed", "pico", "mg",
]

/// Marks the `$EDITOR` value in the login shell's stdout, so noise printed by shell startup files is ignored.
public let editorProbeMarker = "<<HYPERMUG>>"

/// Environment variable that carries the file path to the editor command (never part of the script text).
public let editorFileEnvVar = "HYPERMUG_FILE"

/// How long the login shell may take to report `$EDITOR`.
public let resolveTimeout: TimeInterval = 3

/// Time between SIGTERM and SIGKILL when the login shell has to be killed.
public let killGrace: TimeInterval = 0.5

/// First word of a shell command line, with surrounding quotes and backslash escapes removed.
public func firstWord(of command: String) -> String {
    var word = ""
    var quote: Character?
    var escaped = false
    var started = false
    for ch in command {
        if escaped {
            word.append(ch)
            escaped = false
        } else if let q = quote {
            if ch == q {
                quote = nil
            } else if ch == "\\" && q == "\"" {
                escaped = true
            } else {
                word.append(ch)
            }
        } else if ch == "\\" {
            escaped = true
            started = true
        } else if ch == "'" || ch == "\"" {
            quote = ch
            started = true
        } else if ch.isWhitespace {
            if started { break }
        } else {
            word.append(ch)
            started = true
        }
    }
    return word
}

/// 0 for a normal exit with status 0; the exit status, or 128 + signal, otherwise.
public func exitCode(waitStatus status: Int32) -> Int32 {
    let signal = status & 0x7f
    return signal == 0 ? (status >> 8) & 0xff : 128 + signal
}

/// Shell script that prints `$EDITOR` between two markers.
public func editorProbeScript() -> String {
    "printf '\(editorProbeMarker)%s\(editorProbeMarker)' \"$EDITOR\""
}

/// Extracts `$EDITOR` from the probe's stdout. nil: the shell timed out, failed, or printed no markers.
/// An empty string means the variable is unset or empty.
public func parseEditorProbe(output: String?, timedOut: Bool, exitCode: Int32) -> String? {
    guard !timedOut, exitCode == 0, let output else { return nil }
    let parts = output.components(separatedBy: editorProbeMarker)
    return parts.count >= 3 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : nil
}

public enum EditorPlan: Equatable {
    /// Open with the default app for the file type; `reason` is a log line.
    case defaultApp(reason: String)
    /// Run this command line in the login shell.
    case run(commandLine: String)
}

/// `$EDITOR` is shell text by convention (like git: "code --wait", quoted paths), so it is run as the shell's own
/// command line. The file path never enters the script: it travels in `editorFileEnvVar`, which bash, zsh and fish
/// (positional "$1" does not exist in fish) all expand safely.
public func editorCommandLine(editor: String) -> String {
    "\(editor) \"$\(editorFileEnvVar)\""
}

public func editorPlan(resolvedEditor: String?) -> EditorPlan {
    guard let editor = resolvedEditor, !editor.isEmpty else {
        return .defaultApp(reason: "no $EDITOR in the login shell; using the default app")
    }
    let name = (firstWord(of: editor) as NSString).lastPathComponent
    if terminalEditors.contains(name) {
        return .defaultApp(reason: "$EDITOR \(name) is a terminal editor; using the default app")
    }
    return .run(commandLine: editorCommandLine(editor: editor))
}

/// `$SHELL` if set (GUI apps often lack it), else the account's login shell, else zsh.
public func pickLoginShell(env: String?, passwdShell: String?) -> String {
    if let env, !env.isEmpty { return env }
    if let passwdShell, !passwdShell.isEmpty { return passwdShell }
    return "/bin/zsh"
}

/// `base` with `extra` laid over it; `extra` wins on conflicts.
public func mergedEnvironment(_ base: [String: String], _ extra: [String: String]) -> [String: String] {
    base.merging(extra) { _, new in new }
}

/// Admission control for "Settings…" clicks: at most one resolution and one editor process outstanding,
/// and no relaunch within `relaunchInterval` of the previous accepted request.
public struct EditorGate {
    static let relaunchInterval: TimeInterval = 2

    private var resolving = false
    private var editorRunning = false
    private var lastLaunch = Date.distantPast

    public init() {}

    /// true: start resolving `$EDITOR` now (the gate is then "resolving" until `resolved`).
    public mutating func admit(now: Date) -> Bool {
        if resolving || editorRunning { return false }
        if now.timeIntervalSince(lastLaunch) < EditorGate.relaunchInterval { return false }
        lastLaunch = now
        resolving = true
        return true
    }

    /// The resolution finished. `launching`: an editor process is about to be started.
    public mutating func resolved(launching: Bool) {
        resolving = false
        editorRunning = launching
    }

    /// The editor process ended (or could not be started: pass a non-zero code).
    /// Returns true when the file must be opened in the default app instead.
    public mutating func editorExited(code: Int32) -> Bool {
        editorRunning = false
        return code != 0
    }
}

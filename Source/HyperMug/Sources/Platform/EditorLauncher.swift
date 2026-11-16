import AppKit
import Foundation
import HyperMugCore

/// Opens a file in the user's `$EDITOR`, resolved from their login shell so PATH and variables
/// match a terminal (a GUI app's own environment has neither). Falls back to the default app
/// for the file type, or TextEdit. Never blocks the main thread or parks a worker thread.
///
/// Decisions (admission, probe parsing, terminal-editor check, command line) are Core's; this file only
/// spawns processes and talks to NSWorkspace. All state is confined to `queue`.
enum EditorLauncher {
    private static let log = makeLogSink(category: "Editor")
    private static let queue = DispatchQueue(label: "\(AppIdentity.bundleID).editor", qos: .userInitiated)
    private static var gate = EditorGate()

    /// A spawned child in its own process group (pgid == pid), reaped exactly once on `queue`.
    private final class Child {
        let pid: pid_t
        var exited = false
        var source: DispatchSourceProcess?
        init(pid: pid_t) { self.pid = pid }
    }

    /// Call on the main thread.
    static func open(_ url: URL) {
        queue.async {
            guard gate.admit(now: Date()) else {
                log(.info, "editor request ignored: already resolving $EDITOR, editor still running, or just launched")
                return
            }
            resolveEditor { editor in
                switch editorPlan(resolvedEditor: editor) {
                case .defaultApp(let reason):
                    gate.resolved(launching: false)
                    log(.info, reason)
                    fallback(url)
                case .run(let commandLine):
                    gate.resolved(launching: true)
                    launchEditor(commandLine: commandLine, url: url)
                }
            }
        }
    }

    private static func fallback(_ url: URL) {
        DispatchQueue.main.async { openInDefaultApp(url) }
    }

    /// Asks the login shell for `$EDITOR`; calls `done` on `queue` with nil on failure or timeout.
    private static func resolveEditor(_ done: @escaping (String?) -> Void) {
        let outPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("hypermug-editor-\(UUID().uuidString)").path
        var timedOut = false

        guard let child = spawn(loginShell(), ["-lic", editorProbeScript()], extraEnvironment: [:], stdoutPath: outPath, onExit: { status in
            defer { try? FileManager.default.removeItem(atPath: outPath) }
            let output = FileManager.default.contents(atPath: outPath).flatMap { String(data: $0, encoding: .utf8) }
            done(parseEditorProbe(output: output, timedOut: timedOut, exitCode: exitCode(waitStatus: status)))
        }) else {
            try? FileManager.default.removeItem(atPath: outPath)
            return done(nil)
        }

        // An interactive login shell can ignore SIGTERM or leave children behind, so signal the whole
        // process group, then SIGKILL it after a short grace period.
        queue.asyncAfter(deadline: .now() + resolveTimeout) {
            guard !child.exited else { return }
            timedOut = true
            log(.error, "resolving $EDITOR timed out after \(Int(resolveTimeout)) s; killing the login shell")
            killpg(child.pid, SIGTERM)
            queue.asyncAfter(deadline: .now() + killGrace) {
                killpg(child.pid, SIGKILL)
            }
        }
    }

    private static func launchEditor(commandLine: String, url: URL) {
        let spawned = spawn(loginShell(), ["-lic", commandLine],
                            extraEnvironment: [editorFileEnvVar: url.path], stdoutPath: nil) { status in
            let code = exitCode(waitStatus: status)
            if gate.editorExited(code: code) {
                log(.error, "$EDITOR failed (status \(code)); using the default app: \(commandLine)")
                fallback(url)
            }
        }
        if spawned == nil {
            _ = gate.editorExited(code: -1)
            log(.error, "could not run $EDITOR: \(commandLine); using the default app")
            fallback(url)
        }
    }

    /// Spawns `executable` in its own process group with stdin and stderr on /dev/null and stdout on
    /// `stdoutPath` (or /dev/null). `onExit` runs on `queue` after the child is reaped. Call on `queue`.
    private static func spawn(
        _ executable: String, _ arguments: [String], extraEnvironment: [String: String],
        stdoutPath: String?, onExit: @escaping (Int32) -> Void
    ) -> Child? {
        var attributes: posix_spawnattr_t? = nil
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP))
        posix_spawnattr_setpgroup(&attributes, 0)

        var actions: posix_spawn_file_actions_t? = nil
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        if let stdoutPath {
            posix_spawn_file_actions_addopen(&actions, 1, stdoutPath, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        } else {
            posix_spawn_file_actions_addopen(&actions, 1, "/dev/null", O_WRONLY, 0)
        }
        posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0)

        let environment = mergedEnvironment(ProcessInfo.processInfo.environment, extraEnvironment)
        let argv = ([executable] + arguments).map { strdup($0) } + [nil]
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }

        var pid: pid_t = 0
        let result = posix_spawn(&pid, executable, &actions, &attributes, argv, envp)
        guard result == 0 else {
            log(.error, "posix_spawn \(executable) failed: \(String(cString: strerror(result)))")
            return nil
        }

        let child = Child(pid: pid)
        let finish: (Int32) -> Void = { status in
            guard !child.exited else { return }
            child.exited = true
            child.source?.cancel()
            child.source = nil
            onExit(status)
        }
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: queue)
        source.setEventHandler {
            var status: Int32 = 0
            if waitpid(pid, &status, 0) == pid { finish(status) }
        }
        child.source = source
        source.resume()
        // The child may have exited before the source was armed.
        var status: Int32 = 0
        if waitpid(pid, &status, WNOHANG) == pid { finish(status) }
        return child
    }

    private static func loginShell() -> String {
        pickLoginShell(
            env: ProcessInfo.processInfo.environment["SHELL"],
            passwdShell: getpwuid(getuid())?.pointee.pw_shell.map { String(cString: $0) }
        )
    }

    /// Default app for the file type, TextEdit if none handles it.
    private static func openInDefaultApp(_ url: URL) {
        let workspace = NSWorkspace.shared
        let configuration = NSWorkspace.OpenConfiguration()
        let report: (NSRunningApplication?, Error?) -> Void = { _, error in
            if let error {
                log(.error, "could not open \(url.path): \(error.localizedDescription)")
            }
        }
        if workspace.urlForApplication(toOpen: url) != nil {
            workspace.open(url, configuration: configuration, completionHandler: report)
        } else {
            let textEdit = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
            workspace.open([url], withApplicationAt: textEdit, configuration: configuration, completionHandler: report)
        }
    }
}

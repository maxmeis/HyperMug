import Foundation
import Darwin
import HyperMugCore

/// Owns child lifetimes on the main actor. Exit sources and deadlines never park a worker thread.
@MainActor
final class ShellExecutor {
    private final class Child {
        enum Phase { case running, terminating, killing }
        let pid: pid_t
        let report: (RuntimeIssue) -> Void
        var phase = Phase.running
        var timedOut = false
        var source: DispatchSourceProcess?
        var deadline: DispatchWorkItem?
        var escalation: DispatchWorkItem?
        init(pid: pid_t, report: @escaping (RuntimeIssue) -> Void) {
            self.pid = pid
            self.report = report
        }
    }

    private var children: [pid_t: Child] = [:]
    private var accepting = true
    private let executable: String
    private let environment: [String: String]
    private let capacity: Int
    private let grace: TimeInterval
    var activeCount: Int { children.count }
    var activeProcessIDs: [pid_t] { Array(children.keys) }

    init(executable: String = "/bin/sh", environment: [String: String] = ProcessInfo.processInfo.environment,
         capacity: Int = 8, grace: TimeInterval = 0.5) {
        self.executable = executable
        self.environment = environment.merging(["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]) { _, new in new }
        self.capacity = capacity
        self.grace = grace
    }

    func run(_ command: String, timeout: TimeInterval, report: @escaping (RuntimeIssue) -> Void) {
        guard accepting else { return }
        guard timeout.isFinite && timeout > 0 && !command.utf8.contains(0) else { report(.shellStart(EINVAL)); return }
        guard children.count < capacity else { report(.shellBusy); return }
        let result = spawn(command)
        guard result.error == 0 else { report(.shellStart(result.error)); return }
        let child = Child(pid: result.pid, report: report)
        children[child.pid] = child
        let source = DispatchSource.makeProcessSource(identifier: child.pid, eventMask: .exit, queue: .main)
        source.setEventHandler { [weak self, weak child] in
            guard let self, let child else { return }
            self.reap(child)
        }
        child.source = source
        source.resume()
        let deadline = DispatchWorkItem { [weak self, weak child] in
            guard let self, let child, self.children[child.pid] === child else { return }
            self.reap(child) // Prefer a real exit at the deadline over a spurious timeout.
            guard self.children[child.pid] === child else { return }
            child.timedOut = true
            child.phase = .terminating
            killpg(child.pid, SIGTERM)
            let escalation = DispatchWorkItem { [weak self, weak child] in
                guard let self, let child, self.children[child.pid] === child else { return }
                // Keep the leader unreaped until here. Its PID/group ID cannot be reused,
                // and TERM-ignoring descendants are killed even if their shell has exited.
                child.phase = .killing
                killpg(child.pid, SIGKILL)
                self.reap(child)
            }
            child.escalation = escalation
            DispatchQueue.main.asyncAfter(deadline: .now() + self.grace, execute: escalation)
            child.report(.shellTimeout(timeout))
        }
        child.deadline = deadline
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: deadline)
        reap(child) // The child may already have exited before its source was armed.
    }

    func shutdown() {
        accepting = false
        for child in Array(children.values) {
            child.deadline?.cancel()
            child.escalation?.cancel()
            child.timedOut = true // App shutdown is not an action failure notification.
            child.phase = .killing
            killpg(child.pid, SIGKILL)
            reap(child)
        }
    }

    private func reap(_ child: Child) {
        guard children[child.pid] === child, child.phase != .terminating else { return }
        var status: Int32 = 0
        var result: pid_t
        repeat { result = waitpid(child.pid, &status, WNOHANG) } while result == -1 && errno == EINTR
        guard result != 0 else { return }
        children.removeValue(forKey: child.pid)
        child.source?.cancel()
        child.source = nil
        child.deadline?.cancel()
        child.escalation?.cancel()
        if !child.timedOut {
            if result == -1 { child.report(.shellStart(errno)) }
            else {
                let code = exitCode(waitStatus: status)
                if code != 0 { child.report(.shellExit(code)) }
            }
        }
    }

    private func spawn(_ command: String) -> (pid: pid_t, error: Int32) {
        var attributes: posix_spawnattr_t?
        var code = posix_spawnattr_init(&attributes)
        guard code == 0 else { return (0, code) }
        defer { posix_spawnattr_destroy(&attributes) }
        var defaults = sigset_t()
        sigemptyset(&defaults)
        for signal in [SIGTERM, SIGINT, SIGQUIT, SIGPIPE, SIGHUP] { sigaddset(&defaults, signal) }
        var mask = sigset_t()
        sigemptyset(&mask)
        let flags = Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_CLOEXEC_DEFAULT)
        for result in [posix_spawnattr_setflags(&attributes, flags), posix_spawnattr_setpgroup(&attributes, 0),
                       posix_spawnattr_setsigdefault(&attributes, &defaults), posix_spawnattr_setsigmask(&attributes, &mask)] {
            if result != 0 { return (0, result) }
        }
        var actions: posix_spawn_file_actions_t?
        code = posix_spawn_file_actions_init(&actions)
        guard code == 0 else { return (0, code) }
        defer { posix_spawn_file_actions_destroy(&actions) }
        for fd in Int32(0)...2 {
            code = posix_spawn_file_actions_addopen(&actions, fd, "/dev/null", fd == 0 ? O_RDONLY : O_WRONLY, 0)
            guard code == 0 else { return (0, code) }
        }
        var argv: [UnsafeMutablePointer<CChar>?] = []
        var envp: [UnsafeMutablePointer<CChar>?] = []
        defer { argv.forEach { free($0) }; envp.forEach { free($0) } }
        for argument in [executable, "-c", command] {
            guard let pointer = strdup(argument) else { return (0, ENOMEM) }
            argv.append(pointer)
        }
        for (key, value) in environment {
            guard let pointer = strdup("\(key)=\(value)") else { return (0, ENOMEM) }
            envp.append(pointer)
        }
        argv.append(nil)
        envp.append(nil)
        var pid: pid_t = 0
        code = posix_spawn(&pid, executable, &actions, &attributes, argv, envp)
        return (pid, code)
    }
}

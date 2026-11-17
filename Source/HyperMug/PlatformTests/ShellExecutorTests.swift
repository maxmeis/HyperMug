import Foundation
import Darwin
import HyperMugCore

@main
struct ShellExecutorChecks {
    @MainActor static func main() async {
        var failures = 0
        var checks = 0
        func check(_ value: Bool, _ message: String) {
            checks += 1
            if !value { failures += 1; print("FAIL: \(message)") }
        }
        @MainActor func drained(_ executor: ShellExecutor) async -> Bool {
            let until = ContinuousClock.now + .seconds(4)
            while executor.activeCount != 0 && ContinuousClock.now < until {
                try? await Task.sleep(for: .milliseconds(10))
            }
            return executor.activeCount == 0
        }
        var issues: [RuntimeIssue] = []
        let runner = ShellExecutor(grace: 0.1)
        for _ in 0..<8 {
            runner.run("exit 0", timeout: 1) { issues.append($0) }
            check(await drained(runner), "fast exit is reaped")
        }
        check(issues.isEmpty, "success is silent")
        runner.run("exit 7", timeout: 1) { issues.append($0) }
        check(await drained(runner), "nonzero exit reaped")
        check(issues == [.shellExit(7)], "nonzero status is reported exactly once")
        issues.removeAll()
        runner.run("sleep 20", timeout: 0.15) { issues.append($0) }
        let pid = runner.activeProcessIDs.first!
        check(getpgid(pid) == pid && pid != getpgrp(), "child is isolated from the app process group")
        check(await drained(runner), "timeout terminates and reaps")
        check(issues == [.shellTimeout(0.15)], "timeout does not also report a signal exit")
        check(kill(pid, 0) == -1 && errno == ESRCH, "timed-out leader is gone")
        issues.removeAll()
        let invalid = ShellExecutor(executable: "/definitely/no/hypermug-shell")
        invalid.run("exit 0", timeout: 1) { issues.append($0) }
        check(issues == [.shellStart(ENOENT)], "spawn failure is actionable")
        runner.run("exit 0", timeout: .nan) { issues.append($0) }
        check(issues.last == .shellStart(EINVAL), "invalid internal deadline is rejected")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hypermug-process-check-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let childFile = directory.appendingPathComponent("child.pid")
        var env = ProcessInfo.processInfo.environment
        env["CHILD_PID_FILE"] = childFile.path
        let group = ShellExecutor(environment: env, grace: 0.15)
        issues.removeAll()
        // The shell leader exits on TERM; its descendant deliberately ignores it.
        group.run(#"/bin/sh -c 'trap "" TERM; echo $$ > "$CHILD_PID_FILE"; exec sleep 20' & wait"#,
                  timeout: 0.3) { issues.append($0) }
        check(await drained(group), "group timeout reaps its leader after escalation")
        let descendant = (try? String(contentsOf: childFile, encoding: .utf8)).flatMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        check(descendant != nil, "descendant actually started")
        if let descendant {
            let until = ContinuousClock.now + .seconds(3)
            while kill(descendant, 0) == 0 && ContinuousClock.now < until { try? await Task.sleep(for: .milliseconds(10)) }
            check(kill(descendant, 0) == -1 && errno == ESRCH, "TERM-ignoring descendant is killed after leader exit")
        }
        check(issues == [.shellTimeout(0.3)], "one notification for the entire timed-out group")

        let limited = ShellExecutor(capacity: 1, grace: 0.1)
        issues.removeAll()
        limited.run("sleep 20", timeout: 2) { issues.append($0) }
        limited.run("exit 0", timeout: 1) { issues.append($0) }
        check(issues == [.shellBusy], "in-flight work is bounded")
        let unrelated = ShellExecutor()
        var unrelatedIssues: [RuntimeIssue] = []
        unrelated.run("sleep 1", timeout: 3) { unrelatedIssues.append($0) }
        let unrelatedPID = unrelated.activeProcessIDs.first!
        limited.shutdown()
        check(await drained(limited), "shutdown cleans up own group")
        check(kill(unrelatedPID, 0) == 0, "shutdown does not signal another group")
        limited.run("exit 1", timeout: 1) { issues.append($0) }
        check(limited.activeCount == 0 && issues == [.shellBusy], "shutdown rejects later work silently")
        check(await drained(unrelated), "unrelated child exits normally")
        check(unrelatedIssues.isEmpty, "unrelated action remains successful")
        runner.shutdown()
        print("ShellExecutor: \(checks) checks, \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }
}

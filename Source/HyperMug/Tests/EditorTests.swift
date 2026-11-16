import Foundation
@testable import HyperMugCore

func editorTests() {
    firstWordCases()
    exitCodeCases()
    probeCases()
    planCases()
    loginShellCases()
    environmentCases()
    gateCases()
}

private func firstWordCases() {
    expectEqual(firstWord(of: "code --wait"), "code")
    expectEqual(firstWord(of: "vim"), "vim")
    expectEqual(firstWord(of: "  \t vim -f"), "vim", "leading whitespace is skipped")
    expectEqual(firstWord(of: ""), "")
    expectEqual(firstWord(of: "   "), "")
    expectEqual(firstWord(of: "\"/Applications/My Editor/bin/edit\" --wait"), "/Applications/My Editor/bin/edit")
    expectEqual(firstWord(of: "'/opt/my tools/nvim' -f"), "/opt/my tools/nvim")
    expectEqual(firstWord(of: "my\\ editor --x"), "my editor")
    expectEqual(firstWord(of: "\"a\\\"b\" c"), "a\"b", "escaped quote inside double quotes")
    expectEqual(firstWord(of: "'a\\b' c"), "a\\b", "backslash is literal inside single quotes")
    expectEqual(firstWord(of: "\"it's\" x"), "it's", "other quote kind inside quotes")
    expectEqual(firstWord(of: "a\"b c\"d e"), "ab cd", "quoted part glued to unquoted parts")
    expectEqual(firstWord(of: "\"\" x"), "", "empty quotes are an empty first word")
    expectEqual(firstWord(of: "vim\\"), "vim", "trailing backslash is dropped")
}

private func exitCodeCases() {
    expectEqual(exitCode(waitStatus: 0), 0)
    expectEqual(exitCode(waitStatus: 3 << 8), 3)
    expectEqual(exitCode(waitStatus: 255 << 8), 255)
    expectEqual(exitCode(waitStatus: 9), 137, "killed by SIGKILL: 128 + 9")
    expectEqual(exitCode(waitStatus: 0x80 | 11), 139, "core-dump flag is ignored: 128 + SIGSEGV")
}

private func probeCases() {
    // The script and the parser must agree: two markers around the printed value.
    let script = editorProbeScript()
    expect(script.hasPrefix("printf "))
    expect(script.contains("\"$EDITOR\""))
    expectEqual(script.components(separatedBy: "<<HYPERMUG>>").count, 3, "exactly two markers")

    let m = "<<HYPERMUG>>"
    expectEqual(parseEditorProbe(output: "\(m)code --wait\(m)", timedOut: false, exitCode: 0), "code --wait")
    expectEqual(parseEditorProbe(output: "Welcome!\n\(m)  vim \n\(m)tail noise", timedOut: false, exitCode: 0), "vim",
                "noise around the markers and padding inside are dropped")
    expectEqual(parseEditorProbe(output: "\(m)\(m)", timedOut: false, exitCode: 0), "", "unset variable")
    expectEqual(parseEditorProbe(output: "\(m)code\(m)", timedOut: true, exitCode: 0), nil, "timed out")
    expectEqual(parseEditorProbe(output: "\(m)code\(m)", timedOut: false, exitCode: 1), nil, "shell failed")
    expectEqual(parseEditorProbe(output: nil, timedOut: false, exitCode: 0), nil, "unreadable output")
    expectEqual(parseEditorProbe(output: "code", timedOut: false, exitCode: 0), nil, "no markers")
    expectEqual(parseEditorProbe(output: "\(m)code", timedOut: false, exitCode: 0), nil, "unterminated marker")
}

private func planCases() {
    func isDefault(_ plan: EditorPlan) -> String? {
        if case .defaultApp(let reason) = plan { return reason }
        return nil
    }

    expect(isDefault(editorPlan(resolvedEditor: nil)) != nil, "no EDITOR")
    expect(isDefault(editorPlan(resolvedEditor: "")) != nil, "empty EDITOR")
    for terminal in ["vim -f", "nvim", "nano", "/usr/bin/nano", "emacs -nw", "hx", "\"/opt/My Tools/nvim\" -f", "'vi'"] {
        let reason = isDefault(editorPlan(resolvedEditor: terminal))
        expect(reason?.contains("terminal editor") == true, "\(terminal) needs a terminal")
    }
    expect(isDefault(editorPlan(resolvedEditor: "vim -f"))?.contains("vim") == true, "reason names the editor")

    expectEqual(editorPlan(resolvedEditor: "cursor"), .run(commandLine: "cursor \"$HYPERMUG_FILE\""))
    expectEqual(editorPlan(resolvedEditor: "code --wait"), .run(commandLine: "code --wait \"$HYPERMUG_FILE\""))
    expectEqual(editorPlan(resolvedEditor: "vimr"), .run(commandLine: "vimr \"$HYPERMUG_FILE\""),
                "only exact terminal-editor names are refused")
    expectEqual(editorPlan(resolvedEditor: "/Applications/Cursor.app/bin/cursor"),
                .run(commandLine: "/Applications/Cursor.app/bin/cursor \"$HYPERMUG_FILE\""))
}

private func loginShellCases() {
    expectEqual(pickLoginShell(env: "/bin/bash", passwdShell: "/usr/bin/fish"), "/bin/bash", "$SHELL wins")
    expectEqual(pickLoginShell(env: "", passwdShell: "/usr/bin/fish"), "/usr/bin/fish", "empty $SHELL")
    expectEqual(pickLoginShell(env: nil, passwdShell: "/usr/bin/fish"), "/usr/bin/fish", "no $SHELL")
    expectEqual(pickLoginShell(env: nil, passwdShell: nil), "/bin/zsh")
    expectEqual(pickLoginShell(env: "", passwdShell: ""), "/bin/zsh")
    expectEqual(pickLoginShell(env: nil, passwdShell: ""), "/bin/zsh")
}

private func environmentCases() {
    let base = ["A": "1", "B": "2"]
    expectEqual(mergedEnvironment(base, ["B": "3", "C": "4"]), ["A": "1", "B": "3", "C": "4"], "extra overrides and adds")
    expectEqual(mergedEnvironment(base, [:]), base)
    expectEqual(mergedEnvironment([:], ["X": "y"]), ["X": "y"])
}

private func gateCases() {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    // One resolution at a time.
    var gate = EditorGate()
    expect(gate.admit(now: t0), "first request is admitted")
    expect(!gate.admit(now: t0 + 60), "refused while resolving, however late")

    // Relaunch interval after a default-app outcome: 2 s measured from the admitted request.
    gate.resolved(launching: false)
    expect(!gate.admit(now: t0 + 1.9), "within 2 s of the last request")
    expect(!gate.admit(now: t0 - 5), "clock going backwards is still too soon")
    expect(gate.admit(now: t0 + 2), "exactly 2 s later")

    // While an editor process runs, nothing else starts.
    gate.resolved(launching: true)
    expect(!gate.admit(now: t0 + 100), "editor still running")
    expect(!gate.editorExited(code: 0), "clean exit needs no fallback")
    expect(gate.admit(now: t0 + 100), "after the editor exited")

    // Failure: the default app takes over, and the gate reopens.
    gate.resolved(launching: true)
    expect(gate.editorExited(code: 1), "non-zero exit falls back to the default app")
    expect(gate.admit(now: t0 + 200), "after a failed editor")
    gate.resolved(launching: true)
    expect(gate.editorExited(code: 137), "killed editor falls back too")
}

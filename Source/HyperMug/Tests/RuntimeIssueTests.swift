import Foundation
@testable import HyperMugCore

func runtimeIssueTests() {
    let issues: [RuntimeIssue] = [.configuration, .shellStart(2), .shellExit(7), .shellTimeout(10), .shellBusy, .shortcut]
    expectEqual(Set(issues.map(\.identifier)).count, issues.count)
    for issue in issues {
        expect(!issue.title.isEmpty && !issue.body.isEmpty, "native issue is actionable")
        var gate = IssueNotificationGate()
        expect(gate.admit(issue, now: 100))
        expect(!gate.admit(issue, now: 101), "repeated issue is suppressed")
        expect(gate.admit(issue, now: 130), "later issue can notify")
    }
    var gate = IssueNotificationGate()
    expect(gate.admit(.configuration, now: 0))
    gate.configurationRecovered()
    expect(gate.admit(.configuration, now: 1), "new failure after recovery is reported")
    expect(gate.admit(.shellTimeout(10), now: 1), "other issue categories do not block each other")
    for value in [1.0, 10, 300] {
        let data = Data("{\"shellTimeoutSeconds\":\(value)}".utf8)
        expectEqual(try? decodeConfig(data).get().config.shellTimeoutSeconds, value)
    }
    for text in [#"{"shellTimeoutSeconds":0}"#, #"{"shellTimeoutSeconds":301}"#, #"{"shellTimeoutSeconds":"long"}"#, #"{"$schema":false}"#] {
        if case .failure = decodeConfig(Data(text.utf8)) { expect(true) } else { expect(false, "invalid file option rejected") }
    }
}

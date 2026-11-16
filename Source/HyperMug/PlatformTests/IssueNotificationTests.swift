import Foundation
import UserNotifications
import HyperMugCore

@MainActor
private final class FakeDelivery: IssueNotificationDelivery {
    var permission = NotificationAccess.allowed
    var asks = 0
    var deliveries: [RuntimeIssue] = []
    var removals = 0
    var failDelivery = false
    var holdRequest = false
    var request: CheckedContinuation<Bool, Never>?
    func access() async -> NotificationAccess { permission }
    func requestAccess() async throws -> Bool {
        asks += 1
        if holdRequest { return await withCheckedContinuation { request = $0 } }
        return false
    }
    func deliver(_ issue: RuntimeIssue) async throws {
        if failDelivery { throw NSError(domain: "FixtureDelivery", code: 1) }
        deliveries.append(issue)
    }
    func removeConfiguration() { removals += 1 }
}

@main
struct NotificationChecks {
    @MainActor static func main() async {
        var checks = 0
        var failures = 0
        func check(_ passed: Bool, _ label: String) {
            checks += 1
            if !passed { failures += 1; print("FAIL: \(label)") }
        }
        @MainActor func eventually(_ condition: () -> Bool) async -> Bool {
            let end = ContinuousClock.now + .seconds(2)
            while !condition() && ContinuousClock.now < end { try? await Task.sleep(for: .milliseconds(10)) }
            return condition()
        }
        do {
            let client = FakeDelivery()
            var logs: [String] = []
            let notices = IssueNotifications(delivery: client) { logs.append($0) }
            notices.report(.configuration)
            check(await eventually { client.deliveries.count == 1 }, "authorized native delivery")
            notices.report(.configuration)
            try? await Task.sleep(for: .milliseconds(30))
            check(client.deliveries.count == 1, "repeated error does not flood notifications")
            notices.configurationRecovered()
            notices.configurationRecovered()
            check(client.removals == 1, "recovery clears once")
            notices.report(.configuration)
            check(await eventually { client.deliveries.count == 2 }, "failure after recovery can notify")
            var opens = 0
            notices.openConfiguration = { opens += 1 }
            notices.handleAction("OPEN_CONFIGURATION")
            notices.handleAction(UNNotificationDefaultActionIdentifier)
            notices.handleAction(UNNotificationDismissActionIdentifier)
            check(opens == 2, "only actionable clicks open the config file")
            check(client.asks == 0 && logs.isEmpty, "authorized use needs no permission prompt")
        }
        do {
            let client = FakeDelivery()
            client.permission = .undecided
            client.holdRequest = true
            let notices = IssueNotifications(delivery: client, record: { _ in })
            notices.report(.configuration)
            notices.report(.shellExit(7))
            check(await eventually { client.request != nil }, "permission request is in context")
            check(client.asks == 1, "one permission request for multiple issues")
            notices.configurationRecovered()
            client.request?.resume(returning: true)
            client.request = nil
            check(await eventually { client.deliveries == [.shellExit(7)] }, "config repaired during permission prompt is not delivered")
        }
        do {
            let client = FakeDelivery()
            client.permission = .denied
            var logs: [String] = []
            let notices = IssueNotifications(delivery: client) { logs.append($0) }
            notices.report(.shellTimeout(10))
            check(await eventually { !logs.isEmpty }, "denial is diagnosable")
            check(client.deliveries.isEmpty && client.asks == 0, "denial is respected without repeated OS prompt")
        }
        do {
            let client = FakeDelivery()
            client.failDelivery = true
            var logs: [String] = []
            let notices = IssueNotifications(delivery: client) { logs.append($0) }
            notices.report(.shellStart(2))
            check(await eventually { !logs.isEmpty }, "delivery error is diagnosed without recursive notification")
            check(logs.count == 1 && client.deliveries.isEmpty, "delivery failure is bounded")
        }
        print("IssueNotifications: \(checks) checks, \(failures) failures; no live permissions changed")
        exit(failures == 0 ? 0 : 1)
    }
}

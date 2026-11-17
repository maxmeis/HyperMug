import AppKit
import UserNotifications
import HyperMugCore

// The adapter boundary permits permission/denial/recovery tests without prompting macOS.
enum NotificationAccess { case undecided, allowed, denied }

@MainActor
protocol IssueNotificationDelivery {
    func access() async -> NotificationAccess
    func requestAccess() async throws -> Bool
    func deliver(_ issue: RuntimeIssue) async throws
    func removeConfiguration()
}

@MainActor
private final class NativeNotificationDelivery: IssueNotificationDelivery {
    private let center = UNUserNotificationCenter.current()

    func prepare(delegate: UNUserNotificationCenterDelegate) {
        center.delegate = delegate
        let open = UNNotificationAction(identifier: "OPEN_CONFIGURATION", title: "Open Configuration", options: .foreground)
        center.setNotificationCategories([UNNotificationCategory(identifier: "HYPERMUG_CONFIGURATION", actions: [open], intentIdentifiers: [])])
    }

    func access() async -> NotificationAccess {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: return .undecided
        case .authorized, .provisional: return .allowed
        default: return .denied
        }
    }
    func requestAccess() async throws -> Bool { try await center.requestAuthorization(options: [.alert]) }
    func deliver(_ issue: RuntimeIssue) async throws {
        let content = UNMutableNotificationContent()
        content.title = issue.title
        content.body = issue.body
        content.categoryIdentifier = "HYPERMUG_CONFIGURATION"
        try await center.add(UNNotificationRequest(identifier: issue.identifier, content: content, trigger: nil))
    }
    func removeConfiguration() {
        center.removeDeliveredNotifications(withIdentifiers: ["configuration"])
        center.removePendingNotificationRequests(withIdentifiers: ["configuration"])
    }
}

/// Nonmodal, permission-aware feedback. Lock-screen content never includes commands or shell output.
@MainActor
final class IssueNotifications: NSObject, UNUserNotificationCenterDelegate {
    private let delivery: IssueNotificationDelivery
    private let record: (String) -> Void
    private var gate = IssueNotificationGate()
    private var pending: [String: RuntimeIssue] = [:]
    private var authorization: Task<Void, Never>?
    private var configurationActive = false
    var openConfiguration: (() -> Void)?

    init(delivery: IssueNotificationDelivery, record: @escaping (String) -> Void) {
        self.delivery = delivery
        self.record = record
        super.init()
    }

    convenience override init() {
        let native = NativeNotificationDelivery()
        let log = makeLogSink(category: "notifications")
        self.init(delivery: native) { text in
            log(.error, text)
            DebugLog.write(text)
        }
        native.prepare(delegate: self)
    }

    func report(_ issue: RuntimeIssue) {
        if issue == .configuration { configurationActive = true }
        guard gate.admit(issue, now: ProcessInfo.processInfo.systemUptime) else { return }
        pending[issue.identifier] = issue
        guard authorization == nil else { return }
        authorization = Task { [weak self] in
            guard let self else { return }
            defer { authorization = nil }
            let allowed: Bool
            switch await delivery.access() {
            case .undecided: allowed = (try? await delivery.requestAccess()) ?? false
            case .allowed: allowed = true
            case .denied: allowed = false
            }
            guard allowed else {
                pending.removeAll()
                record("Native notifications unavailable; inspect configuration and Doctor activity or enable notifications in macOS Settings")
                return
            }
            // Reports arriving across awaits are coalesced by category into this same delivery task.
            while !pending.isEmpty {
                let notices = pending.values.sorted { $0.identifier < $1.identifier }
                pending.removeAll()
                for notice in notices {
                    if notice == .configuration && !configurationActive { continue }
                    do { try await delivery.deliver(notice) }
                    catch { record("Cannot deliver native notification: \(error.localizedDescription)") }
                    if notice == .configuration && !configurationActive { delivery.removeConfiguration() }
                }
            }
        }
    }

    func configurationRecovered() {
        guard configurationActive else { return }
        configurationActive = false
        pending.removeValue(forKey: "configuration")
        gate.configurationRecovered()
        delivery.removeConfiguration()
    }

    func handleAction(_ identifier: String) {
        if identifier == UNNotificationDefaultActionIdentifier || identifier == "OPEN_CONFIGURATION" { openConfiguration?() }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let identifier = response.actionIdentifier
        Task { @MainActor [weak self] in self?.handleAction(identifier) }
        completionHandler()
    }
}

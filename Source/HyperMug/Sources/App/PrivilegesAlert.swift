import AppKit
import HyperMugCore

/// `Check Privileges…`: one alert at a time. The content and button actions come from Core.
enum PrivilegesPresenter {
    private static var gate = ModalGate()

    /// Call on the main thread.
    static func present() {
        guard gate.tryEnter() else { return }
        // Run the modal from a run-loop block, not a GCD main-queue block, so the main queue keeps
        // draining (config watchers, timers) while the alert is up.
        RunLoop.main.perform(inModes: [.common]) {
            show()
            gate.leave()
        }
    }

    private static func show() {
        let model = privilegesAlert(
            accessibility: accessibilityTrusted(),
            inputMonitoring: inputMonitoringAccess() == .granted
        )
        let alert = NSAlert()
        alert.messageText = model.title
        alert.informativeText = model.body
        alert.alertStyle = model.warning ? .warning : .informational
        for button in model.buttons { alert.addButton(withTitle: button.title) }
        // Return must trigger OK (the last button), not the first one.
        for button in alert.buttons { button.keyEquivalent = "" }
        alert.buttons.last?.keyEquivalent = "\r"

        NSApp.activate(ignoringOtherApps: true)
        let index = alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        switch privilegeAction(responseIndex: index, in: model) {
        case .requestAccessibility: PrivilegeActions.requestAccessibility()
        case .requestInputMonitoring: PrivilegeActions.requestInputMonitoring()
        case .restart: PrivilegeActions.relaunch()
        case .none: break
        }
    }
}

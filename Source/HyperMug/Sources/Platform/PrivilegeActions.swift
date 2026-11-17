import AppKit
import Foundation
import HyperMugCore

/// The side effects behind the privileges alert's buttons.
enum PrivilegeActions {
    private static let log = makeLogSink(category: "Privileges")
    /// Composition root protects unsaved JSON before a relaunch helper is started. Main thread only.
    static var confirmRelaunch: ((_ completion: @escaping (Bool) -> Void) -> Void)?

    /// Shows the system Accessibility prompt and opens the pane.
    static func requestAccessibility() {
        promptAccessibility()
        openPane(accessibilityPaneURL)
    }

    /// Triggers the system Input Monitoring prompt (answered off-main) and opens the pane.
    static func requestInputMonitoring() {
        requestInputMonitoringAccess { _ in }
        openPane(inputMonitoringPaneURL)
    }

    /// Relaunches HyperMug: a detached shell reopens the bundle after this process has quit, and terminating
    /// through NSApp runs applicationWillTerminate, so the engine shuts down cleanly first.
    static func relaunch() {
        if let confirmRelaunch { confirmRelaunch { if $0 { performRelaunch() } } }
        else { performRelaunch() }
    }

    private static func performRelaunch() {
        let command = relaunchCommand(bundlePath: Bundle.main.bundlePath)
        let relauncher = Process()
        relauncher.executableURL = URL(fileURLWithPath: command.path)
        relauncher.arguments = command.arguments
        relauncher.standardInput = FileHandle.nullDevice
        relauncher.standardOutput = FileHandle.nullDevice
        relauncher.standardError = FileHandle.nullDevice
        do {
            try relauncher.run()   // not waited on; it outlives this process
        } catch {
            log(.error, "could not start the relauncher: \(error.localizedDescription)")
            return   // stay running instead of quitting
        }
        NSApp.terminate(nil)
    }

    private static func openPane(_ pane: String) {
        if let url = URL(string: pane) { NSWorkspace.shared.open(url) }
    }
}

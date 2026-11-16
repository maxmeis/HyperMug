import AppKit

/// Explains the manual system setup required before three and four finger swipes can be used.
enum TrackpadSetup {
    static func present() {
        let alert = NSAlert()
        alert.messageText = "Trackpad Swipes"
        alert.informativeText = "Configure threeFingerSwipe and fourFingerSwipe actions in your HyperMug JSON settings. In System Settings → Trackpad, disable conflicting Mission Control, App Exposé, and full-screen app swipe assignments. Disable three-finger drag in Accessibility → Pointer Control if it is enabled.\n\nOmitted directions run no HyperMug action. Native assignments you disable remain disabled until you re-enable them in System Settings."
        alert.addButton(withTitle: "Open Trackpad Settings")
        alert.addButton(withTitle: "Done")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension")!)
        }
    }
}

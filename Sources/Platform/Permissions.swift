import ApplicationServices
import Foundation
import HyperMugCore
import IOKit.hid

func accessibilityTrusted() -> Bool {
    AXIsProcessTrusted()
}

/// Shows the system Accessibility prompt if the app is not trusted yet.
func promptAccessibility() {
    _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
}

func inputMonitoringAccess() -> HIDAccess {
    switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
    case kIOHIDAccessTypeGranted: return .granted
    case kIOHIDAccessTypeDenied: return .denied
    default: return .unknown
    }
}

/// Triggers the Input Monitoring system prompt. `IOHIDRequestAccess` blocks until the user answers,
/// so it runs off the main thread; `done` is called on the main thread with the answer.
func requestInputMonitoringAccess(_ done: @escaping (Bool) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
        let granted = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        DispatchQueue.main.async { done(granted) }
    }
}

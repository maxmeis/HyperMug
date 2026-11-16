import AppKit
import HyperMugCore

enum DoctorReader {
    static func preferences() -> [DoctorPreference] {
        let keys: [(String, String, DoctorAction)] = [
            ("Three-finger horizontal swipes", "TrackpadThreeFingerHorizSwipeGesture", .trackpad),
            ("Four-finger horizontal swipes", "TrackpadFourFingerHorizSwipeGesture", .trackpad),
            ("Three-finger vertical swipes", "TrackpadThreeFingerVertSwipeGesture", .trackpad),
            ("Four-finger vertical swipes", "TrackpadFourFingerVertSwipeGesture", .trackpad),
            ("Three-finger dragging", "TrackpadThreeFingerDrag", .pointer)]
        let domains = [("Built-in trackpad", "com.apple.AppleMultitouchTrackpad"),
                       ("External trackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad")]
        return domains.flatMap { label, domain in
            keys.map { name, key, action in
                let value = CFPreferencesCopyValue(key as CFString, domain as CFString,
                    kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
                    ?? CFPreferencesCopyValue(key as CFString, domain as CFString,
                        kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
                return DoctorPreference(name: "\(label): \(name)", value: (value as? NSNumber)?.intValue, action: action)
            }
        }
    }

    static func runningApps() -> [String] {
        NSWorkspace.shared.runningApplications.compactMap { $0.localizedName }
    }
}

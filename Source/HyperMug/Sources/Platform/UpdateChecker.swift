import AppKit
import Sparkle

/// Retained for the life of the app; Sparkle owns automatic checks and the install UI.
final class UpdateChecker {
    private let controller: SPUStandardUpdaterController?
    private var menuObservation: NSKeyValueObservation?
    private var started = false

    init() {
        let info = Bundle.main.infoDictionary ?? [:]
        let feed = (info["SUFeedURL"] as? String).flatMap(URL.init(string:))
        let key = info["SUPublicEDKey"] as? String ?? ""
        if let feed, feed.scheme == "https", feed.host != nil, !key.isEmpty {
            // Apply the configured preference before Sparkle schedules its first check.
            controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        } else {
            controller = nil
            NSLog("HyperMug: updates disabled (no valid Sparkle feed and public key)")
        }
    }

    func apply(autoUpdate: Bool) {
        guard let controller else { return }
        if controller.updater.automaticallyChecksForUpdates != autoUpdate {
            controller.updater.automaticallyChecksForUpdates = autoUpdate
        }
        if !started {
            controller.startUpdater()
            started = true
        }
    }

    func configureMenuItem(_ item: NSMenuItem) {
        if let controller {
            item.target = controller
            item.action = #selector(SPUStandardUpdaterController.checkForUpdates(_:))
            // The status menu disables AppKit's automatic item validation.
            menuObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak item] updater, _ in
                item?.isEnabled = updater.canCheckForUpdates
            }
        } else {
            item.isEnabled = false
            item.toolTip = "Updates are unavailable in this build"
        }
    }
}

import AppKit
import HyperMugCore

/// Shows the config error alert. One alert at a time (`AlertQueue`); an error that arrives while one is
/// showing is shown afterwards if it is still the file's current error.
final class ConfigErrorAlert {
    private let store: ConfigStore
    private var queue = AlertQueue<ConfigError>()

    init(store: ConfigStore) {
        self.store = store
    }

    func present(_ error: ConfigError) {
        if let next = queue.arrive(error) { show(next) }
    }

    private func show(_ error: ConfigError) {
        // Never run the modal loop inside a file watcher handler, nor inside a GCD main-queue
        // block: the main queue does not drain while the alert is up, which would stall the
        // config watchers and their debounce. A run-loop block runs outside the queue.
        RunLoop.main.perform(inModes: [.common]) { [self] in
            let text = configErrorAlertText(error, configPath: (store.url.path as NSString).abbreviatingWithTildeInPath)
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = text.title
            alert.informativeText = text.body
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
            if let next = queue.dismissed(stillCurrent: store.error) { show(next) }
        }
    }
}

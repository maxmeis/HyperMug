import AppKit
import HyperMugCore

/// Shows the result of an update check. "Open GitHub" + "OK" iff the alert carries a URL, else just "OK".
func presentUpdateAlert(_ model: UpdateAlert) {
    let alert = NSAlert()
    alert.messageText = model.title
    alert.informativeText = model.text
    alert.alertStyle = .informational
    if model.openURL != nil {
        alert.addButton(withTitle: "Open GitHub")
    }
    alert.addButton(withTitle: "OK")
    if alert.runModal() == .alertFirstButtonReturn, let url = model.openURL {
        NSWorkspace.shared.open(url)
    }
}

import AppKit
import HyperMugCore

/// Menu bar icon. Clicking opens the native menu; its Stay Awake checkbox toggles Caffeine for the
/// running session (never written to the config). All click decisions live in Core `StatusLogic`.
final class StatusItemController: NSObject {
    private let store: ConfigStore
    private let engine: Engine
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var stayAwakeItem: NSMenuItem!
    private lazy var settingsWindow = SettingsWindowController(url: store.url)
    private var tracker = SecureInputTracker()
    private var secureItem: NSMenuItem?
    private var secureSeparator: NSMenuItem?
    private var secureTimer: Timer?
    /// Details window; each refresh re-polls so "seen since" stays owned by this controller.
    private lazy var secureWindow = SecureInputWindowController { [weak self] in
        self?.pollSecureInput()
        return (self?.tracker.info, self?.tracker.since)
    }

    init(store: ConfigStore, engine: Engine, updateChecker: UpdateChecker) {
        self.store = store
        self.engine = engine
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        let settings = NSMenuItem(title: MenuText.settings, action: #selector(openSettings), keyEquivalent: ",")
        settings.keyEquivalentModifierMask = [.command]
        let stayAwake = NSMenuItem(title: "Stay Awake", action: #selector(toggleCaffeine), keyEquivalent: "")
        stayAwake.target = self
        stayAwakeItem = stayAwake
        let privileges = NSMenuItem(title: MenuText.privileges, action: #selector(checkPrivileges), keyEquivalent: "")
        let trackpad = NSMenuItem(title: "Trackpad Swipes…", action: #selector(showTrackpadSetup), keyEquivalent: "")
        let updates = NSMenuItem(title: MenuText.updates, action: nil, keyEquivalent: "")
        let quit = NSMenuItem(title: MenuText.quit, action: #selector(quit), keyEquivalent: "q")
        quit.keyEquivalentModifierMask = [.command]
        for item in [settings, trackpad, privileges, quit] { item.target = self }
        updateChecker.configureMenuItem(updates)

        menu.autoenablesItems = false
        menu.addItem(stayAwake)
        menu.addItem(.separator())
        menu.addItem(settings)
        menu.addItem(trackpad)
        menu.addItem(privileges)
        menu.addItem(updates)
        menu.addItem(.separator())
        menu.addItem(quit)

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.pollSecureInput() }
        RunLoop.main.add(timer, forMode: .common)
        secureTimer = timer
        pollSecureInput()
        refresh()
    }

    func refresh() {
        stayAwakeItem.state = engine.caffeineOn ? .on : .off
        let icon = statusIcon(caffeineOn: engine.caffeineOn, secureHolderName: tracker.info?.holder.name)
        let image = NSImage(systemSymbolName: icon.symbol, accessibilityDescription: icon.label)
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    @objc private func clicked() {
        guard let event = NSApp.currentEvent else { return }
        let kind: MouseUpKind
        switch event.type {
        case .leftMouseUp: kind = .left
        case .rightMouseUp: kind = .right
        default: kind = .other
        }
        switch classifyStatusClick(kind, controlHeld: event.modifierFlags.contains(.control)) {
        case .showMenu:
            // Re-read Secure Input so the first item is current when the menu opens.
            pollSecureInput()
            // A menu attached only for this click keeps left-click free for the Caffeine toggle.
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        }
    }

    @objc private func toggleCaffeine() {
        engine.toggleCaffeine()
    }

    /// Main-thread poll (2 s timer, common modes so it also runs while the menu or an alert is open).
    /// Keeps the latest details for the window; the icon and menu change only when the holder changes.
    private func pollSecureInput() {
        guard tracker.update(SecureInputReader.current(), now: Date()) else { return }
        updateSecureMenuItems()
        refresh()
    }

    /// `Blocked by Secure Input: <app>…` plus a separator at the top of the menu while active; nothing otherwise.
    private func updateSecureMenuItems() {
        if let item = secureItem {
            menu.removeItem(item)
            secureItem = nil
        }
        if let separator = secureSeparator {
            menu.removeItem(separator)
            secureSeparator = nil
        }
        guard let title = secureMenuTitle(holderName: tracker.info?.holder.name) else { return }
        let item = NSMenuItem(title: title, action: #selector(showSecureInputWindow), keyEquivalent: "")
        item.target = self
        let separator = NSMenuItem.separator()
        menu.insertItem(item, at: 0)
        menu.insertItem(separator, at: 1)
        secureItem = item
        secureSeparator = separator
    }

    @objc private func showSecureInputWindow() {
        secureWindow.show(anchor: statusItem.button)
    }

    @objc private func openSettings() {
        store.createIfAbsent()
        settingsWindow.present()
    }

    @objc private func checkPrivileges() {
        PrivilegesPresenter.present()
    }

    @objc private func showTrackpadSetup() { TrackpadSetup.present() }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

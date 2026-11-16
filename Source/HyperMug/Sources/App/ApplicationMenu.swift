import AppKit
import HyperMugCore

/// Standard menus keep keyboard commands available while a HyperMug window is active.
enum ApplicationMenu {
    static func install(settingsTarget: AnyObject, settingsAction: Selector, doctorAction: Selector) {
        let main = NSMenu()
        let app = NSMenu(title: AppIdentity.appName)
        app.addItem(withTitle: "About \(AppIdentity.appName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        let settings = app.addItem(withTitle: "Settings…", action: settingsAction, keyEquivalent: ",")
        settings.target = settingsTarget
        let doctor = app.addItem(withTitle: "Doctor…", action: doctorAction, keyEquivalent: "d")
        doctor.keyEquivalentModifierMask = [.command, .shift]
        doctor.target = settingsTarget
        app.addItem(.separator())
        app.addItem(withTitle: "Hide \(AppIdentity.appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(.separator())
        app.addItem(withTitle: "Quit \(AppIdentity.appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        add(app, to: main)

        let edit = NSMenu(title: "Edit")
        for (title, action, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"),
                                     ("Copy", "copy:", "c"), ("Paste", "paste:", "v"),
                                     ("Select All", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        add(edit, to: main)
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        add(window, to: main)
        NSApp.windowsMenu = window
        NSApp.mainMenu = main
    }

    private static func add(_ menu: NSMenu, to main: NSMenu) {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        main.addItem(item)
    }
}


extension Notification.Name {
    static let showHyperMugDoctor = Notification.Name("HyperMugShowDoctor")
}

import Foundation
@testable import HyperMugCore

func statusLogicTests() {
    // Icon: a Secure Input holder wins over the Caffeine state and is named in the label.
    for caffeineOn in [true, false] {
        expectEqual(statusIcon(caffeineOn: caffeineOn, secureHolderName: "Safari"),
                    StatusIcon(symbol: "lock.fill", label: "HyperMug — Blocked by Secure Input (Safari)"),
                    "secure holder overrides caffeine=\(caffeineOn)")
    }
    // Without a holder the icon follows Caffeine: filled mug on, empty mug off.
    expectEqual(statusIcon(caffeineOn: true, secureHolderName: nil),
                StatusIcon(symbol: "mug.fill", label: "HyperMug — Caffeine on"))
    expectEqual(statusIcon(caffeineOn: false, secureHolderName: nil),
                StatusIcon(symbol: "mug", label: "HyperMug — Caffeine off"))

    // Every status-item click opens the menu; caffeine changes only from its checkbox item.
    expectEqual(classifyStatusClick(.right, controlHeld: false), .showMenu)
    expectEqual(classifyStatusClick(.right, controlHeld: true), .showMenu)
    expectEqual(classifyStatusClick(.left, controlHeld: true), .showMenu)
    expectEqual(classifyStatusClick(.left, controlHeld: false), .showMenu)
    expectEqual(classifyStatusClick(.other, controlHeld: false), .showMenu)
    expectEqual(classifyStatusClick(.other, controlHeld: true), .showMenu)

    // First menu item exists only while Secure Input is held, and names the holder.
    expectEqual(secureMenuTitle(holderName: nil), nil)
    expectEqual(secureMenuTitle(holderName: "1Password"), "Blocked by Secure Input: 1Password…")

    // Config error alert: names the app, carries the reason and the file path.
    let text = configErrorAlertText(ConfigError(reason: "capsLock must be \"default\", \"meh\" or \"hyper\""),
                                    configPath: "~/.config/hypermug.toml")
    expectEqual(text.title, "HyperMug config error")
    expectEqual(text.body,
                "capsLock must be \"default\", \"meh\" or \"hyper\"\n\n~/.config/hypermug.toml — last good config stays active.")
}

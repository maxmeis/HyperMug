import Foundation

/// Menu bar icon: SF Symbol name plus its accessibility label.
public struct StatusIcon: Equatable {
    public let symbol: String
    public let label: String

    public init(symbol: String, label: String) {
        self.symbol = symbol
        self.label = label
    }
}

private let secureInputBlockedText = "Blocked by Secure Input"

/// Lock = Secure Input is held by an app (event taps get no keystrokes); otherwise filled mug = Caffeine on.
public func statusIcon(caffeineOn: Bool, secureHolderName: String?) -> StatusIcon {
    if let holder = secureHolderName {
        return StatusIcon(symbol: "lock.fill",
                          label: "\(AppIdentity.appName) — \(secureInputBlockedText) (\(holder))")
    }
    return StatusIcon(symbol: caffeineOn ? "mug.fill" : "mug",
                      label: "\(AppIdentity.appName) — Caffeine \(caffeineOn ? "on" : "off")")
}

/// The kind of mouse-up that reached the status item button.
public enum MouseUpKind: Equatable { case left, right, other }

public enum StatusClick: Equatable { case showMenu }

/// Every supported status-item click opens the native menu.
public func classifyStatusClick(_ kind: MouseUpKind, controlHeld: Bool) -> StatusClick {
    .showMenu
}

/// First menu item while Secure Input is held (`Blocked by Secure Input: <app>…`); nil when it is not.
public func secureMenuTitle(holderName: String?) -> String? {
    holderName.map { "\(secureInputBlockedText): \($0)…" }
}

public enum MenuText {
    public static let settings = "Settings…"
    public static let privileges = "Check Privileges…"
    public static let quit = "Quit \(AppIdentity.appName)"
}

/// Alert for an invalid config file. `configPath` is the display path of the file.
public func configErrorAlertText(_ e: ConfigError, configPath: String) -> (title: String, body: String) {
    ("\(AppIdentity.appName) config error",
     "\(e.reason)\n\n\(configPath) — last good config stays active.")
}

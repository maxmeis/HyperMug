import Foundation

/// A snapshot for an explicit Save/Cancel settings window. The caller reads and writes files;
/// Core validates and merges without discarding keys from a newer schema.
public struct SettingsEdit {
    public let original: Data
    public let config: AppConfig

    public init(_ data: Data) throws {
        switch decodeConfig(data) {
        case .success(let decoded): config = decoded.config
        case .failure(let error): throw error
        }
        original = data
    }

    public func save(_ draft: AppConfig, current: Data) throws -> Data {
        guard current == original else {
            throw ConfigError(reason: "The config file changed outside Settings. Reload it before saving your edits.")
        }
        // decodeConfig already established that this snapshot is a JSON object.
        var root = try JSONSerialization.jsonObject(with: current) as! [String: Any]
        root["capsLock"] = draft.capsLock.rawValue
        root["caffeineOnLaunch"] = draft.caffeineOnLaunch
        root["launchAtLogin"] = draft.launchAtLogin
        root["autoUpdate"] = draft.autoUpdate
        var mouse = root["mouse"] as? [String: Any] ?? [:]
        var scroll = mouse["invertScroll"] as? [String: Any] ?? [:]
        scroll["vertical"] = draft.mouse.invertScroll.vertical
        scroll["horizontal"] = draft.mouse.invertScroll.horizontal
        mouse["invertScroll"] = scroll
        var buttons = mouse["buttons"] as? [String: Any] ?? [:]
        patch(&buttons, "back", old: config.mouse.buttons.back, new: draft.mouse.buttons.back)
        patch(&buttons, "forward", old: config.mouse.buttons.forward, new: draft.mouse.buttons.forward)
        patch(&buttons, "thumb", old: config.mouse.buttons.thumb, new: draft.mouse.buttons.thumb)
        mouse["buttons"] = buttons
        root["mouse"] = mouse
        var trackpad = root["trackpad"] as? [String: Any] ?? [:]
        patchSwipe(&trackpad, "threeFingerSwipe", old: config.trackpad.threeFingerSwipe, new: draft.trackpad.threeFingerSwipe)
        patchSwipe(&trackpad, "fourFingerSwipe", old: config.trackpad.fourFingerSwipe, new: draft.trackpad.fourFingerSwipe)
        root["trackpad"] = trackpad
        let result = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        switch decodeConfig(result) {
        case .success: return result
        case .failure(let error): throw error
        }
    }
}

private func patch(_ object: inout [String: Any], _ key: String, old: ButtonAction?, new: ButtonAction?) {
    guard old != new else { return }
    var action = object[key] as? [String: Any] ?? [:]
    action.removeValue(forKey: "shortcut")
    action.removeValue(forKey: "shell")
    switch new {
    case .shortcut(let shortcut): action["shortcut"] = shortcut.tokens
    case .shell(let command): action["shell"] = command
    case nil: break
    }
    if action.isEmpty { object.removeValue(forKey: key) } else { object[key] = action }
}

private func patchSwipe(_ trackpad: inout [String: Any], _ key: String, old: SwipeMap, new: SwipeMap) {
    var swipes = trackpad[key] as? [String: Any] ?? [:]
    patch(&swipes, "up", old: old.up, new: new.up)
    patch(&swipes, "down", old: old.down, new: new.down)
    patch(&swipes, "left", old: old.left, new: new.left)
    patch(&swipes, "right", old: old.right, new: new.right)
    if swipes.isEmpty { trackpad.removeValue(forKey: key) } else { trackpad[key] = swipes }
}

/// One text field per action, with an explicit type picker in the UI.
public func settingsAction(kind: String, text: String) -> Result<ButtonAction?, ConfigError> {
    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    switch kind {
    case "none": return .success(nil)
    case "shell":
        guard !value.isEmpty else { return .failure(ConfigError(reason: "Shell command cannot be empty")) }
        return .success(.shell(value))
    case "shortcut":
        let tokens = value.split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == "+" }).map(String.init)
        switch parseShortcut(tokens) {
        case .success(let shortcut): return .success(.shortcut(shortcut))
        case .failure(let error): return .failure(error)
        }
    default: return .failure(ConfigError(reason: "Unknown action type"))
    }
}

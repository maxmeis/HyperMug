import Foundation

public enum DoctorState: String {
    case passed, warning, blocked, unknown, inactive
}

public enum DoctorAction {
    case none, accessibility, inputMonitoring, trackpad, pointer, config
}

public struct DoctorCheck {
    public let title: String
    public let detail: String
    public let state: DoctorState
    public let action: DoctorAction

    public init(_ title: String, _ detail: String, _ state: DoctorState, _ action: DoctorAction = .none) {
        self.title = title
        self.detail = detail
        self.state = state
        self.action = action
    }
}

public struct DoctorPreference {
    public let name: String
    public let value: Int?
    public let action: DoctorAction

    public init(name: String, value: Int?, action: DoctorAction = .trackpad) {
        self.name = name
        self.value = value
        self.action = action
    }
}

public func doctorPermissionChecks(accessibility: Bool, inputMonitoring: Bool) -> [DoctorCheck] {
    [DoctorCheck("Accessibility", accessibility ? "HyperMug can run shortcuts and read input events."
        : "Allow HyperMug in System Settings to use input controls.",
        accessibility ? .passed : .blocked, accessibility ? .none : .accessibility),
     DoctorCheck("Input Monitoring", inputMonitoring ? "HyperMug has access to keyboard, mouse, and trackpad input."
        : "Allow HyperMug in System Settings. Then restart HyperMug.",
        inputMonitoring ? .passed : .blocked, inputMonitoring ? .none : .inputMonitoring)]
}

public func doctorConflictChecks(preferences: [DoctorPreference], runningApps: [String],
                                  secureInputHolder: String?) -> [DoctorCheck] {
    var checks = [DoctorCheck("Secure Input", secureInputHolder.map { "\($0) has Secure Input enabled. Keyboard controls can be blocked." }
        ?? "No app has Secure Input enabled.", secureInputHolder == nil ? .passed : .warning)]
    for preference in preferences {
        let detail = preference.value.map { $0 == 0 ? "The saved macOS setting is off."
            : "A macOS assignment is enabled. Check for a conflicting gesture in System Settings." }
        checks.append(DoctorCheck(preference.name, detail ?? "macOS did not expose this setting. Check it in System Settings.",
            preference.value.map { $0 == 0 ? .passed : .warning } ?? .unknown, preference.action))
    }
    let remappers = ["hyperkey", "openlogi", "bettertouchtool", "karabiner-elements", "swipeswitcher", "logi options+"]
    for app in runningApps where remappers.contains(app.lowercased()) {
        checks.append(DoctorCheck(app, "This app can handle the same inputs. Check its mappings.", .warning))
    }
    return checks
}

public func doctorCaptureCheck(hasMappings: Bool, enabled: Bool, devices: Int, error: String?) -> DoctorCheck {
    guard hasMappings else { return DoctorCheck("Trackpad", "No swipe actions are configured.", .inactive, .config) }
    guard enabled else { return DoctorCheck("Trackpad", "Capture is stopped. Check the required permissions.", .blocked) }
    if let error { return DoctorCheck("Trackpad", error, .blocked) }
    guard devices > 0 else { return DoctorCheck("Trackpad", "No supported trackpad was found.", .warning) }
    return DoctorCheck("Trackpad", "Listening on \(devices) trackpad device(s). Try a swipe and check Activity.", .passed)
}

public func doctorConfigCheck(error: String?, unknownKeys: [String] = [], notice: ConfigNotice? = nil) -> DoctorCheck {
    let note = notice.map { " " + $0.message } ?? ""
    if let error { return DoctorCheck("Configuration", "\(error)\(note) The last valid settings remain active.", .blocked, .config) }
    if !unknownKeys.isEmpty {
        return DoctorCheck("Configuration", "These settings are ignored: \(unknownKeys.joined(separator: ", ")). Check the setting names.", .warning, .config)
    }
    if case .legacyIgnored? = notice { return DoctorCheck("Configuration", "Your settings loaded successfully.\(note)", .warning, .config) }
    return DoctorCheck("Configuration", "Your settings loaded successfully.\(note)", .passed, .config)
}

public func doctorActionLabel(_ action: ButtonAction?) -> String {
    switch action {
    case .none: return "Not assigned"
    case .shortcut: return "Keyboard shortcut"
    case .helper(let name): return "Helper: \(name)"
    case .shell(let command):
        if command.contains("aerospace workspace") {
            if command.hasSuffix("next") { return "Next AeroSpace workspace" }
            if command.hasSuffix("prev") { return "Previous AeroSpace workspace" }
        }
        return "Shell command"
    }
}

public func doctorSummary(_ checks: [DoctorCheck]) -> DoctorCheck {
    if checks.contains(where: { $0.state == .blocked }) {
        return DoctorCheck("Action required", "Resolve the blocked checks to restore all configured controls.", .blocked)
    }
    if checks.contains(where: { $0.state == .warning }) {
        return DoctorCheck("Review possible conflicts", "Input controls are available. Some settings need your review.", .warning)
    }
    if checks.contains(where: { $0.state == .unknown }) {
        return DoctorCheck("Manual check needed", "Some macOS settings cannot be checked automatically.", .unknown)
    }
    return DoctorCheck("Checks passed", "No problems were found by these checks.", .passed)
}

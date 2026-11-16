import CoreGraphics
import Foundation

// Secure Event Input: who holds it, may we offer to quit it, and the texts of the details panel.
// All OS reads (IORegistry, process facts) happen in Platform/SecureInputReader.swift and arrive here as plain values.

/// One entry of the `IOConsoleUsers` array of the IORegistry root.
public struct SecureInputSession: Equatable {
    public var userName: String?
    public var uid: UInt32?
    public var onConsole: Bool?
    public var secureInputPID: Int32?

    public init(userName: String? = nil, uid: UInt32? = nil, onConsole: Bool? = nil, secureInputPID: Int32? = nil) {
        self.userName = userName
        self.uid = uid
        self.onConsole = onConsole
        self.secureInputPID = secureInputPID
    }
}

/// Raw facts about one process, as read by Platform. Strings may be empty; `makeHolder` normalizes them.
public struct ProcessFacts: Equatable {
    public var pid: Int32
    public var localizedName: String?
    /// Kernel process name (`proc_name`).
    public var processName: String?
    public var bundleID: String?
    public var bundlePath: String?
    public var executablePath: String?
    /// Kernel executable path (`proc_pidpath`).
    public var kernelPath: String?
    public var ownerName: String?
    public var ownerUID: UInt32?
    public var isFrontmost: Bool
    /// True when an `NSRunningApplication` exists for the process (it can be activated / asked to quit).
    public var hasApp: Bool

    public init(
        pid: Int32, localizedName: String? = nil, processName: String? = nil, bundleID: String? = nil,
        bundlePath: String? = nil, executablePath: String? = nil, kernelPath: String? = nil,
        ownerName: String? = nil, ownerUID: UInt32? = nil, isFrontmost: Bool = false, hasApp: Bool = false
    ) {
        self.pid = pid
        self.localizedName = localizedName
        self.processName = processName
        self.bundleID = bundleID
        self.bundlePath = bundlePath
        self.executablePath = executablePath
        self.kernelPath = kernelPath
        self.ownerName = ownerName
        self.ownerUID = ownerUID
        self.isFrontmost = isFrontmost
        self.hasApp = hasApp
    }
}

/// The process that currently holds macOS Secure Event Input (password fields etc.).
/// While it is held, event taps receive no keystrokes. `pid == 0` means it is enabled but the holder is unknown.
public struct SecureInputHolder: Equatable {
    public let pid: Int32
    public let name: String
    /// Kernel process name, nil when unknown. Used for the protected-process check.
    public let processName: String?
    public let bundleID: String?
    public let path: String?
    public let ownerName: String?
    public let ownerUID: UInt32?
    public let isFrontmost: Bool
    public let hasApp: Bool

    public init(
        pid: Int32, name: String, processName: String? = nil, bundleID: String? = nil, path: String? = nil,
        ownerName: String? = nil, ownerUID: UInt32? = nil, isFrontmost: Bool = false, hasApp: Bool = false
    ) {
        self.pid = pid
        self.name = name
        self.processName = processName
        self.bundleID = bundleID
        self.path = path
        self.ownerName = ownerName
        self.ownerUID = ownerUID
        self.isFrontmost = isFrontmost
        self.hasApp = hasApp
    }
}

/// Everything known while Secure Event Input is on.
public struct SecureInputInfo: Equatable {
    public let holder: SecureInputHolder
    public let sessions: [SecureInputSession]

    public init(holder: SecureInputHolder, sessions: [SecureInputSession]) {
        self.holder = holder
        self.sessions = sessions
    }
}

/// Enabled, but macOS names no owner.
public let unknownSecureInputHolder = SecureInputHolder(pid: 0, name: "unknown app")

// MARK: - Resolving the holder

private let kCGSSessionUserNameKey = "kCGSSessionUserNameKey"
private let kCGSSessionUserIDKey = "kCGSSessionUserIDKey"
private let kCGSSessionOnConsoleKey = "kCGSSessionOnConsoleKey"
private let kCGSSessionSecureInputPIDKey = "kCGSSessionSecureInputPID"

/// The `IOConsoleUsers` entries as sessions. A key with a missing or wrongly typed value becomes nil.
public func parseConsoleUsers(_ raw: [[String: Any]]) -> [SecureInputSession] {
    raw.map { entry in
        SecureInputSession(
            userName: entry[kCGSSessionUserNameKey] as? String,
            uid: (entry[kCGSSessionUserIDKey] as? NSNumber)?.uint32Value,
            onConsole: (entry[kCGSSessionOnConsoleKey] as? NSNumber)?.boolValue,
            secureInputPID: (entry[kCGSSessionSecureInputPIDKey] as? NSNumber)?.int32Value)
    }
}

/// The holder PID from the console user's session: on-console and current uid preferred.
public func chooseHolderPID(_ sessions: [SecureInputSession], currentUID: UInt32) -> Int32? {
    let candidates = sessions.filter { ($0.secureInputPID ?? 0) > 0 }
    let chosen = candidates.first { $0.onConsole == true && $0.uid == currentUID }
        ?? candidates.first { $0.onConsole == true }
        ?? candidates.first { $0.uid == currentUID }
        ?? candidates.first
    return chosen?.secureInputPID
}

private func firstNonEmpty(_ values: String?...) -> String? {
    values.lazy.compactMap { $0 }.first { !$0.isEmpty }
}

/// Display name: localized name, else kernel process name, else `PID n`. Path: bundle, else executable, else kernel path.
public func makeHolder(_ facts: ProcessFacts) -> SecureInputHolder {
    let processName = firstNonEmpty(facts.processName)
    return SecureInputHolder(
        pid: facts.pid,
        name: firstNonEmpty(facts.localizedName, processName) ?? "PID \(facts.pid)",
        processName: processName,
        bundleID: facts.bundleID,
        path: firstNonEmpty(facts.bundlePath, facts.executablePath, facts.kernelPath),
        ownerName: facts.ownerName,
        ownerUID: facts.ownerUID,
        isFrontmost: facts.isFrontmost,
        hasApp: facts.hasApp)
}

/// Holder and sessions for the current Secure Input state. `resolve` reads fresh facts for the chosen PID.
public func secureInputInfo(
    sessions: [SecureInputSession], currentUID: UInt32, resolve: (Int32) -> ProcessFacts
) -> SecureInputInfo {
    guard let pid = chooseHolderPID(sessions, currentUID: currentUID) else {
        return SecureInputInfo(holder: unknownSecureInputHolder, sessions: sessions)
    }
    return SecureInputInfo(holder: makeHolder(resolve(pid)), sessions: sessions)
}

// MARK: - Protection

private let protectedProcessNames: Set<String> = ["loginwindow", "WindowServer", "SecurityAgent", "kernel_task", "launchd"]

/// One-line reason why Quit / Force Quit must not be offered for this holder; nil when allowed.
public func protectionReason(_ holder: SecureInputHolder, selfPID: Int32, currentUID: UInt32) -> String? {
    if holder.pid == 0 { return "macOS reports no owner for Secure Input." }
    if holder.pid <= 1 { return "PID \(holder.pid) is a system process." }
    if holder.pid == selfPID { return "This is \(AppIdentity.appName) itself." }
    guard let owner = holder.ownerUID else { return "The owner of PID \(holder.pid) cannot be determined." }
    if owner != currentUID { return "The process belongs to another user (\(holder.ownerName ?? "uid \(owner)"))." }
    for candidate in [holder.name, holder.processName] {
        if let candidate, protectedProcessNames.contains(candidate) { return "\(candidate) is a protected system process." }
    }
    return nil
}

// MARK: - Tracking across polls

/// Latest Secure Input state plus the time of the first poll that saw it on.
public struct SecureInputTracker {
    public init() {}
    public private(set) var info: SecureInputInfo?
    public private(set) var since: Date?

    /// Records the newest poll. Returns true when the holder identity (pid or name) differs from the previous poll,
    /// i.e. when the icon and menu need a refresh. `since` is set on off→on and cleared on →off.
    public mutating func update(_ new: SecureInputInfo?, now: Date) -> Bool {
        let previous = info?.holder
        let wasOn = info != nil
        info = new
        if new == nil {
            since = nil
        } else if !wasOn {
            since = now
        }
        return new?.holder.pid != previous?.pid || new?.holder.name != previous?.name
    }
}

// MARK: - Details panel text

/// Everything the details panel shows. `—` marks an unknown or inapplicable value.
public struct SecureInputPanelModel: Equatable {
    public let status: String
    public let since: String
    public let app: String
    public let pid: String
    public let bundleID: String
    public let path: String
    public let owner: String
    public let frontmost: String
    public let sessions: String
    public let reason: String
    public let bringEnabled: Bool
    public let quitEnabled: Bool
    public let forceQuitEnabled: Bool
}

private let noValue = "—"

/// `info == nil` means Secure Input is off. `protection` is `protectionReason` for the holder; nil allows Quit / Force Quit.
public func secureInputPanelModel(info: SecureInputInfo?, sinceText: String?, protection: String?) -> SecureInputPanelModel {
    guard let info else {
        return SecureInputPanelModel(
            status: "Secure Input is off", since: noValue, app: noValue, pid: noValue, bundleID: noValue, path: noValue,
            owner: noValue, frontmost: noValue, sessions: noValue, reason: "",
            bringEnabled: false, quitEnabled: false, forceQuitEnabled: false)
    }
    let holder = info.holder
    let known = holder.pid != 0
    return SecureInputPanelModel(
        status: "Secure Input is on",
        since: sinceText ?? noValue,
        app: known ? holder.name : "unknown app (macOS reports no owner)",
        pid: known ? String(holder.pid) : noValue,
        bundleID: known ? holder.bundleID ?? noValue : noValue,
        path: known ? holder.path ?? noValue : noValue,
        owner: known ? ownerText(holder) : noValue,
        frontmost: known ? (holder.isFrontmost ? "yes" : "no") : noValue,
        sessions: info.sessions.isEmpty ? "none reported" : info.sessions.map(describeSession).joined(separator: "\n"),
        reason: protection.map { "Quit and Force Quit are disabled: \($0)" } ?? "",
        bringEnabled: holder.hasApp,
        quitEnabled: protection == nil,
        forceQuitEnabled: protection == nil)
}

private func ownerText(_ holder: SecureInputHolder) -> String {
    guard let uid = holder.ownerUID else { return noValue }
    return holder.ownerName.map { "\($0) (uid \(uid))" } ?? "uid \(uid)"
}

public func describeSession(_ s: SecureInputSession) -> String {
    let user = s.userName ?? "?"
    let uid = s.uid.map(String.init) ?? "?"
    let console = s.onConsole.map { $0 ? "yes" : "no" } ?? "?"
    let pid = s.secureInputPID.map(String.init) ?? "none"
    return "user \(user) · uid \(uid) · on console \(console) · secure input PID \(pid)"
}

// MARK: - Termination

public struct TerminationPrompt: Equatable {
    public let title: String
    public let body: String
    public let confirmButton: String
}

public func terminationPrompt(holderName: String, pid: Int32, force: Bool) -> TerminationPrompt {
    let verb = force ? "Force Quit" : "Quit"
    return TerminationPrompt(
        title: "\(verb) \(holderName) (PID \(pid))?",
        body: force
            ? "The process is killed immediately. Unsaved changes in it are lost."
            : "The app is asked to quit. It may ask to save first, or refuse.",
        confirmButton: verb)
}

/// SIGKILL (9) for Force Quit, SIGTERM (15) otherwise.
public func terminationSignal(force: Bool) -> Int32 {
    force ? 9 : 15
}

public func terminationFailureTitle(force: Bool, name: String, pid: Int32) -> String {
    "Could not \(force ? "force quit" : "quit") \(name) (PID \(pid))"
}

// MARK: - Panel placement

/// Just below the status item (`anchor`, screen coordinates), right-aligned to it, kept inside `visible`.
/// nil when there is no anchor: the caller centers the panel.
public func panelOrigin(anchor: CGRect?, panelSize: CGSize, visible: CGRect?) -> CGPoint? {
    guard let anchor else { return nil }
    var origin = CGPoint(x: anchor.maxX - panelSize.width, y: anchor.minY - panelSize.height - 4)
    if let visible {
        origin.x = min(max(origin.x, visible.minX), max(visible.minX, visible.maxX - panelSize.width))
        origin.y = min(max(origin.y, visible.minY), max(visible.minY, visible.maxY - panelSize.height))
    }
    return origin
}

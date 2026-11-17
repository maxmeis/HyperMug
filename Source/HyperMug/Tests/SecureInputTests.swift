import CoreGraphics
import Foundation
@testable import HyperMugCore

func secureInputTests() {
    secureInputParseConsoleUsers()
    secureInputChooseHolderPID()
    secureInputMakeHolder()
    secureInputResolveInfo()
    secureInputProtection()
    secureInputTrackerBehavior()
    secureInputPanelModelOff()
    secureInputPanelModelOn()
    secureInputDescribeSession()
    secureInputTermination()
    secureInputPanelPlacement()
}

// MARK: - Fixtures

private let me: UInt32 = 501

private func session(uid: UInt32? = me, console: Bool? = true, pid: Int32?, user: String? = "max") -> SecureInputSession {
    SecureInputSession(userName: user, uid: uid, onConsole: console, secureInputPID: pid)
}

private func holder(
    pid: Int32 = 123, name: String = "Safari", processName: String? = "Safari", bundleID: String? = nil, path: String? = nil,
    ownerName: String? = "max", ownerUID: UInt32? = me, isFrontmost: Bool = false, hasApp: Bool = true
) -> SecureInputHolder {
    SecureInputHolder(
        pid: pid, name: name, processName: processName, bundleID: bundleID, path: path, ownerName: ownerName,
        ownerUID: ownerUID, isFrontmost: isFrontmost, hasApp: hasApp)
}

// MARK: - IOConsoleUsers parsing

private func secureInputParseConsoleUsers() {
    expectEqual(parseConsoleUsers([]), [], "no entries")

    // IORegistry hands back NSNumber values.
    let full: [String: Any] = [
        "kCGSSessionUserNameKey": "max",
        "kCGSSessionUserIDKey": NSNumber(value: 501),
        "kCGSSessionOnConsoleKey": NSNumber(value: true),
        "kCGSSessionSecureInputPID": NSNumber(value: 4242),
    ]
    expectEqual(parseConsoleUsers([full]), [SecureInputSession(userName: "max", uid: 501, onConsole: true, secureInputPID: 4242)])

    let off: [String: Any] = ["kCGSSessionOnConsoleKey": NSNumber(value: false)]
    expectEqual(parseConsoleUsers([off]), [SecureInputSession(onConsole: false)], "false is not nil")

    expectEqual(parseConsoleUsers([[:]]), [SecureInputSession()], "missing keys")

    let wrongTypes: [String: Any] = [
        "kCGSSessionUserNameKey": 7,
        "kCGSSessionUserIDKey": "501",
        "kCGSSessionOnConsoleKey": "yes",
        "kCGSSessionSecureInputPID": "4242",
    ]
    expectEqual(parseConsoleUsers([wrongTypes]), [SecureInputSession()], "wrong types become nil")

    let second: [String: Any] = ["kCGSSessionUserNameKey": "guest", "kCGSSessionSecureInputPID": NSNumber(value: 9)]
    expectEqual(
        parseConsoleUsers([full, second]).map(\.userName), ["max", "guest"], "order is kept")
}

// MARK: - Choosing the holder PID

private func secureInputChooseHolderPID() {
    expectEqual(chooseHolderPID([], currentUID: me), nil, "no sessions")
    expectEqual(
        chooseHolderPID([session(pid: nil), session(pid: 0), session(pid: -3)], currentUID: me), nil,
        "missing, zero and negative PIDs are not holders")

    let other = session(uid: 7, console: false, pid: 1)
    let mineBackground = session(uid: me, console: false, pid: 2)
    let othersConsole = session(uid: 7, console: true, pid: 3)
    let mineConsole = session(uid: me, console: true, pid: 4)
    expectEqual(chooseHolderPID([other, mineBackground, othersConsole, mineConsole], currentUID: me), 4, "console + uid first")
    expectEqual(chooseHolderPID([other, mineBackground, othersConsole], currentUID: me), 3, "then console")
    expectEqual(chooseHolderPID([other, mineBackground], currentUID: me), 2, "then own uid")
    expectEqual(chooseHolderPID([other], currentUID: me), 1, "then first candidate")
    expectEqual(
        chooseHolderPID([session(uid: me, console: true, pid: 8), session(uid: me, console: true, pid: 9)], currentUID: me), 8,
        "ties go to the first")
    expectEqual(
        chooseHolderPID([session(pid: nil), other], currentUID: me), 1, "sessions without a PID are skipped")
}

// MARK: - Holder construction

private func secureInputMakeHolder() {
    let full = makeHolder(ProcessFacts(
        pid: 42, localizedName: "Safari", processName: "Safari-kernel", bundleID: "com.apple.Safari",
        bundlePath: "/Applications/Safari.app", executablePath: "/Applications/Safari.app/Contents/MacOS/Safari",
        kernelPath: "/kernel/path", ownerName: "max", ownerUID: me, isFrontmost: true, hasApp: true))
    expectEqual(
        full,
        SecureInputHolder(
            pid: 42, name: "Safari", processName: "Safari-kernel", bundleID: "com.apple.Safari",
            path: "/Applications/Safari.app", ownerName: "max", ownerUID: me, isFrontmost: true, hasApp: true),
        "localized name and bundle path win")

    let noLocalized = makeHolder(ProcessFacts(pid: 7, localizedName: "", processName: "helperd"))
    expectEqual(noLocalized.name, "helperd", "empty localized name falls back to the process name")
    expectEqual(makeHolder(ProcessFacts(pid: 7, localizedName: nil, processName: "helperd")).name, "helperd")
    expectEqual(makeHolder(ProcessFacts(pid: 7, localizedName: "", processName: "")).name, "PID 7", "nothing usable")
    expectEqual(makeHolder(ProcessFacts(pid: 8)).name, "PID 8")
    expectEqual(makeHolder(ProcessFacts(pid: 7, processName: "")).processName, nil, "empty process name is unknown")

    expectEqual(
        makeHolder(ProcessFacts(pid: 1, bundlePath: "", executablePath: "/exe", kernelPath: "/k")).path, "/exe",
        "empty bundle path falls through to the executable")
    expectEqual(makeHolder(ProcessFacts(pid: 1, executablePath: nil, kernelPath: "/k")).path, "/k", "then the kernel path")
    expectEqual(makeHolder(ProcessFacts(pid: 1, bundlePath: "", executablePath: "", kernelPath: "")).path, nil, "no path")

    let bare = makeHolder(ProcessFacts(pid: 5))
    expectEqual(bare.hasApp, false)
    expectEqual(bare.isFrontmost, false)
    expectEqual(bare.ownerUID, nil)
}

private func secureInputResolveInfo() {
    var resolved: [Int32] = []
    let sessions = [session(uid: 7, console: false, pid: 1), session(pid: 4)]
    let info = secureInputInfo(sessions: sessions, currentUID: me) { pid in
        resolved.append(pid)
        return ProcessFacts(pid: pid, exists: true, localizedName: "Terminal", ownerUID: me, hasApp: true)
    }
    expectEqual(resolved, [4], "facts are read once, for the chosen PID")
    expectEqual(info.holder.pid, 4)
    expectEqual(info.holder.name, "Terminal")
    expectEqual(info.sessions, sessions)

    let stale = secureInputInfo(sessions: [session(pid: 44)], currentUID: me) { pid in
        ProcessFacts(pid: pid, exists: false)
    }
    expectEqual(stale.holder, unknownSecureInputHolder, "a stale IORegistry PID is not a holder")
    expectEqual(stale.sessions, [session(pid: 44)], "raw session diagnostics keep the stale PID")

    var called = false
    let sessionsWithoutPID = [session(pid: nil)]
    let unknown = secureInputInfo(sessions: sessionsWithoutPID, currentUID: me) { pid in
        called = true
        return ProcessFacts(pid: pid)
    }
    expectEqual(called, false, "no PID, nothing to resolve")
    expectEqual(unknown.holder, unknownSecureInputHolder)
    expectEqual(unknown.holder.pid, 0)
    expectEqual(unknown.holder.name, "unknown app")
    expectEqual(unknown.sessions, sessionsWithoutPID)
}

// MARK: - Quit protection

private func secureInputProtection() {
    let selfPID: Int32 = 50
    func reason(_ h: SecureInputHolder) -> String? { protectionReason(h, selfPID: selfPID, currentUID: me) }

    expectEqual(reason(holder(pid: 0, ownerUID: nil)), "macOS reports no owner for Secure Input.", "pid 0 first")
    expectEqual(reason(holder(pid: 1)), "PID 1 is a system process.")
    expectEqual(reason(holder(pid: -5)), "PID -5 is a system process.", "negative PIDs are system PIDs")
    expectEqual(reason(holder(pid: 2)), nil, "PID 2 is an ordinary process")

    expectEqual(reason(holder(pid: selfPID, ownerUID: nil)), "This is HyperMug itself.", "own PID beats the owner checks")
    expectEqual(reason(holder(pid: selfPID, ownerUID: 0)), "This is HyperMug itself.")

    expectEqual(reason(holder(pid: 77, ownerUID: nil)), "The owner of PID 77 cannot be determined.")
    expectEqual(
        reason(holder(pid: 77, ownerName: "root", ownerUID: 0)), "The process belongs to another user (root).")
    expectEqual(
        reason(holder(pid: 77, ownerName: nil, ownerUID: 0)), "The process belongs to another user (uid 0).")
    expectEqual(
        reason(holder(pid: 77, name: "loginwindow", processName: "loginwindow", ownerName: "root", ownerUID: 0)),
        "The process belongs to another user (root).", "another user is reported before the protected name")

    for name in ["loginwindow", "WindowServer", "SecurityAgent", "kernel_task", "launchd"] {
        expectEqual(reason(holder(pid: 77, name: name, processName: nil)), "\(name) is a protected system process.", name)
    }
    expectEqual(
        reason(holder(pid: 77, name: "Login Window", processName: "WindowServer")),
        "WindowServer is a protected system process.", "protected by the kernel process name only")

    expectEqual(reason(holder(pid: 77, name: "Safari", processName: "Safari")), nil, "ordinary app")
    expectEqual(reason(holder(pid: 77, name: "Safari", processName: nil)), nil, "unknown process name")
    expectEqual(reason(holder(pid: 77, name: "loginwindow2", processName: "xlaunchd")), nil, "exact match only")
}

// MARK: - Tracker

private func secureInputTrackerBehavior() {
    let t0 = Date(timeIntervalSince1970: 1_000)
    let t1 = Date(timeIntervalSince1970: 1_002)
    let t2 = Date(timeIntervalSince1970: 1_004)
    let t3 = Date(timeIntervalSince1970: 1_006)
    let t4 = Date(timeIntervalSince1970: 1_008)
    let safari = SecureInputInfo(holder: holder(pid: 10, name: "Safari"), sessions: [session(pid: 10)])
    let safariAgain = SecureInputInfo(holder: holder(pid: 10, name: "Safari"), sessions: [session(pid: 10), session(uid: 8, pid: 11)])
    let renamed = SecureInputInfo(holder: holder(pid: 10, name: "Safari Technology Preview"), sessions: [])
    let terminal = SecureInputInfo(holder: holder(pid: 11, name: "Terminal"), sessions: [])

    var tracker = SecureInputTracker()
    expectEqual(tracker.info, nil)
    expectEqual(tracker.since, nil)

    expectEqual(tracker.update(nil, now: t0), false, "off and staying off")
    expectEqual(tracker.since, nil)

    expectEqual(tracker.update(safari, now: t1), true, "off to on")
    expectEqual(tracker.since, t1, "since is the first poll that saw it on")
    expectEqual(tracker.info, safari)

    expectEqual(tracker.update(safariAgain, now: t2), false, "same holder")
    expectEqual(tracker.since, t1, "since is kept")
    expectEqual(tracker.info, safariAgain, "details are refreshed")

    expectEqual(tracker.update(renamed, now: t2), true, "same pid, new name")
    expectEqual(tracker.since, t1)
    expectEqual(tracker.update(terminal, now: t3), true, "holder changed")
    expectEqual(tracker.since, t1, "on to on keeps since")

    expectEqual(tracker.update(nil, now: t3), true, "on to off")
    expectEqual(tracker.since, nil)
    expectEqual(tracker.info, nil)

    expectEqual(tracker.update(safari, now: t4), true)
    expectEqual(tracker.since, t4, "a new episode starts a new since")
}

// MARK: - Panel text

private func secureInputPanelModelOff() {
    let model = secureInputPanelModel(info: nil, sinceText: "ignored", protection: "ignored")
    expectEqual(model.status, "Secure Input is off")
    for value in [model.since, model.app, model.pid, model.bundleID, model.path, model.owner, model.frontmost, model.sessions] {
        expectEqual(value, "—")
    }
    expectEqual(model.reason, "")
    expectEqual(model.bringEnabled, false)
    expectEqual(model.quitEnabled, false)
    expectEqual(model.forceQuitEnabled, false)
}

private func secureInputPanelModelOn() {
    // Enabled but unknown owner.
    let unknownInfo = SecureInputInfo(holder: unknownSecureInputHolder, sessions: [])
    let unknown = secureInputPanelModel(
        info: unknownInfo, sinceText: nil, protection: "macOS reports no owner for Secure Input.")
    expectEqual(unknown.status, "Secure Input is on")
    expectEqual(unknown.since, "—")
    expectEqual(unknown.app, "unknown app (macOS reports no owner)")
    for value in [unknown.pid, unknown.bundleID, unknown.path, unknown.owner, unknown.frontmost] { expectEqual(value, "—") }
    expectEqual(unknown.sessions, "none reported")
    expectEqual(unknown.reason, "Quit and Force Quit are disabled: macOS reports no owner for Secure Input.")
    expectEqual(unknown.bringEnabled, false)
    expectEqual(unknown.quitEnabled, false)
    expectEqual(unknown.forceQuitEnabled, false)

    // Fully known, quit allowed.
    let known = holder(
        pid: 123, name: "Safari", bundleID: "com.apple.Safari", path: "/Applications/Safari.app", ownerName: "max",
        ownerUID: me, isFrontmost: true, hasApp: true)
    let sessions = [session(pid: 123), session(uid: nil, console: nil, pid: nil, user: nil)]
    let model = secureInputPanelModel(
        info: SecureInputInfo(holder: known, sessions: sessions), sinceText: "10:15:00", protection: nil)
    expectEqual(model.status, "Secure Input is on")
    expectEqual(model.since, "10:15:00")
    expectEqual(model.app, "Safari")
    expectEqual(model.pid, "123")
    expectEqual(model.bundleID, "com.apple.Safari")
    expectEqual(model.path, "/Applications/Safari.app")
    expectEqual(model.owner, "max (uid 501)")
    expectEqual(model.frontmost, "yes")
    expectEqual(
        model.sessions,
        "user max · uid 501 · on console yes · secure input PID 123\nuser ? · uid ? · on console ? · secure input PID none",
        "one line per session")
    expectEqual(model.reason, "")
    expectEqual(model.bringEnabled, true)
    expectEqual(model.quitEnabled, true)
    expectEqual(model.forceQuitEnabled, true)

    // Unknown details, no app object, quit blocked by a protection reason.
    let sparse = holder(
        pid: 9, name: "PID 9", processName: nil, bundleID: nil, path: nil, ownerName: nil, ownerUID: 0,
        isFrontmost: false, hasApp: false)
    let blocked = secureInputPanelModel(
        info: SecureInputInfo(holder: sparse, sessions: []), sinceText: nil,
        protection: "The process belongs to another user (uid 0).")
    expectEqual(blocked.bundleID, "—")
    expectEqual(blocked.path, "—")
    expectEqual(blocked.owner, "uid 0", "owner without a name")
    expectEqual(blocked.frontmost, "no")
    expectEqual(blocked.bringEnabled, false, "no app object, nothing to activate")
    expectEqual(blocked.quitEnabled, false)
    expectEqual(blocked.forceQuitEnabled, false)
    expectEqual(blocked.reason, "Quit and Force Quit are disabled: The process belongs to another user (uid 0).")

    let noOwner = secureInputPanelModel(
        info: SecureInputInfo(holder: holder(pid: 9, ownerName: nil, ownerUID: nil), sessions: []), sinceText: nil,
        protection: "The owner of PID 9 cannot be determined.")
    expectEqual(noOwner.owner, "—", "unknown owner")

    // Bring to Front depends on the app object only; Quit on the protection only.
    let appButNoQuit = secureInputPanelModel(
        info: SecureInputInfo(holder: holder(hasApp: true), sessions: []), sinceText: nil, protection: "protected")
    expectEqual(appButNoQuit.bringEnabled, true)
    expectEqual(appButNoQuit.quitEnabled, false)
    let quitButNoApp = secureInputPanelModel(
        info: SecureInputInfo(holder: holder(hasApp: false), sessions: []), sinceText: nil, protection: nil)
    expectEqual(quitButNoApp.bringEnabled, false)
    expectEqual(quitButNoApp.quitEnabled, true)
}

private func secureInputDescribeSession() {
    expectEqual(describeSession(SecureInputSession()), "user ? · uid ? · on console ? · secure input PID none")
    expectEqual(
        describeSession(SecureInputSession(userName: "max", uid: 501, onConsole: true, secureInputPID: 99)),
        "user max · uid 501 · on console yes · secure input PID 99")
    expectEqual(
        describeSession(SecureInputSession(userName: "guest", uid: 502, onConsole: false, secureInputPID: nil)),
        "user guest · uid 502 · on console no · secure input PID none")
}

// MARK: - Termination

private func secureInputTermination() {
    expectEqual(
        terminationPrompt(holderName: "Safari", pid: 12, force: false),
        TerminationPrompt(
            title: "Quit Safari (PID 12)?", body: "The app is asked to quit. It may ask to save first, or refuse.",
            confirmButton: "Quit"))
    expectEqual(
        terminationPrompt(holderName: "Safari", pid: 12, force: true),
        TerminationPrompt(
            title: "Force Quit Safari (PID 12)?",
            body: "The process is killed immediately. Unsaved changes in it are lost.", confirmButton: "Force Quit"))

    expectEqual(terminationSignal(force: false), SIGTERM)
    expectEqual(terminationSignal(force: true), SIGKILL)

    expectEqual(terminationFailureTitle(force: false, name: "Safari", pid: 12), "Could not quit Safari (PID 12)")
    expectEqual(terminationFailureTitle(force: true, name: "Safari", pid: 12), "Could not force quit Safari (PID 12)")
}

// MARK: - Placement

private func secureInputPanelPlacement() {
    let size = CGSize(width: 560, height: 470)
    let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
    func anchor(maxX: CGFloat, minY: CGFloat) -> CGRect { CGRect(x: maxX - 30, y: minY, width: 30, height: 24) }

    expectEqual(panelOrigin(anchor: nil, panelSize: size, visible: visible), nil, "no anchor: caller centers")

    // Right-aligned to the item, 4 pt below it.
    expectEqual(
        panelOrigin(anchor: anchor(maxX: 1000, minY: 800), panelSize: size, visible: nil),
        CGPoint(x: 440, y: 326), "without a screen the raw origin is used")
    expectEqual(
        panelOrigin(anchor: anchor(maxX: 1000, minY: 800), panelSize: size, visible: visible),
        CGPoint(x: 440, y: 326), "inside the screen nothing moves")

    expectEqual(panelOrigin(anchor: anchor(maxX: 300, minY: 800), panelSize: size, visible: visible)?.x, 0, "clamped left")
    expectEqual(panelOrigin(anchor: anchor(maxX: 2000, minY: 800), panelSize: size, visible: visible)?.x, 880, "clamped right")
    expectEqual(panelOrigin(anchor: anchor(maxX: 1000, minY: 100), panelSize: size, visible: visible)?.y, 0, "clamped bottom")
    expectEqual(panelOrigin(anchor: anchor(maxX: 1000, minY: 1500), panelSize: size, visible: visible)?.y, 430, "clamped top")

    let small = CGRect(x: 10, y: 20, width: 500, height: 400)
    expectEqual(
        panelOrigin(anchor: anchor(maxX: 400, minY: 300), panelSize: CGSize(width: 2000, height: 2000), visible: small),
        CGPoint(x: 10, y: 20), "a panel larger than the screen sticks to its lower left")
}

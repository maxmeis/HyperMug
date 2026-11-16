import Foundation
import CoreGraphics
@testable import HyperMugCore

private let keyBits: CGEventMask = (1 << CGEventType.keyDown.rawValue) |
    (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
private let mouseBits: CGEventMask = (1 << CGEventType.otherMouseDown.rawValue) | (1 << CGEventType.otherMouseUp.rawValue)
private let scrollBit: CGEventMask = 1 << CGEventType.scrollWheel.rawValue
private let ms: UInt64 = 1_000_000

private let backAction = ButtonAction.shell("back-cmd")
private let thumbAction = ButtonAction.shell("thumb-cmd")

/// Records every call in order, so tests can assert on what the engine asked the OS to do.
private final class FakePorts: EnginePorts {
    var trusted = true
    var access = HIDAccess.granted
    var installResult = true
    var acquireResult = true
    var loginStatus = LoginItemStatus.notRegistered
    var loginError: String?

    var calls: [String] = []
    var ran: [ButtonAction] = []
    var logs: [String] = []
    var errors: [String] = []
    var debugLines: [String] = []

    func count(_ call: String) -> Int { calls.filter { $0 == call }.count }
    func count(prefix: String) -> Int { calls.filter { $0.hasPrefix(prefix) }.count }
    func clear() { calls = []; ran = []; logs = []; errors = []; debugLines = [] }

    func accessibilityTrusted() -> Bool { trusted }
    func promptAccessibility() { calls.append("prompt") }
    func inputMonitoringAccess() -> HIDAccess { access }
    func installTap(mask: CGEventMask) -> Bool { calls.append("install:\(String(mask, radix: 16))"); return installResult }
    func removeTap() { calls.append("removeTap") }
    func setCapsKeyboardMonitoring(_ on: Bool) { calls.append("caps:\(on)") }
    func acquireCaffeine() -> Bool { calls.append("acquire"); return acquireResult }
    func releaseCaffeine() { calls.append("release") }
    func loginItemStatus() -> LoginItemStatus { loginStatus }
    func setLoginItem(registered: Bool) -> String? { calls.append("login:\(registered)"); return loginError }
    func setThumbDiversion(_ on: Bool) { calls.append("thumb:\(on)") }
    func shutdownThumb() { calls.append("shutdownThumb") }
    func run(_ action: ButtonAction) { ran.append(action) }
    func postEscape() { calls.append("escape") }
    func log(_ level: LogLevel, _ message: String) {
        if level == .error { errors.append(message) } else { logs.append(message) }
    }
    func debugLog(_ line: String) { debugLines.append(line) }
}

private func config(caffeine: Bool = false, caps: CapsMode = .default, login: Bool = false,
                    back: ButtonAction? = nil, thumb: ButtonAction? = nil, vertical: Bool = false) -> AppConfig {
    var c = AppConfig()
    c.capsLock = caps
    c.caffeineOnLaunch = caffeine
    c.launchAtLogin = login
    c.mouse.buttons.back = back
    c.mouse.buttons.thumb = thumb
    c.mouse.invertScroll.vertical = vertical
    return c
}

private func makeEngine() -> (Engine, FakePorts) {
    let ports = FakePorts()
    return (Engine(ports: ports), ports)
}

func engineTests() {
    startTests()
    caffeineTests()
    thumbTests()
    loginItemTests()
    tapLifecycleTests()
    capsMonitoringTests()
    swallowedButtonTests()
    capsEventTests()
    tapEventTests()
    stateChangeTests()
    shutdownTests()
}

private func startTests() {
    let (engine, ports) = makeEngine()
    ports.trusted = false
    ports.access = .denied
    engine.start()
    expectEqual(ports.calls, ["prompt"])
    expectEqual(ports.debugLines, ["AXIsProcessTrusted=false IOHIDCheckAccess(listen)=denied"])
    // start() applies nothing and syncs nothing.
    expectEqual(ports.logs, [])
    expect(!engine.caffeineOn, "start does not touch caffeine")
}

// MARK: - Caffeine (R7: the config only supplies the initial value; the click is session-only)

private func caffeineTests() {
    let (engine, ports) = makeEngine()
    engine.apply(config(caffeine: true))
    expect(engine.caffeineOn, "first apply sets caffeine from caffeineOnLaunch")
    expectEqual(ports.count("acquire"), 1)

    engine.apply(config(caffeine: true, caps: .meh))
    expectEqual(ports.count("acquire"), 1)

    engine.toggleCaffeine()
    expect(!engine.caffeineOn, "toggle turns it off for this session")
    expectEqual(ports.count("release"), 1)

    // An unrelated config edit must not flip the session state back.
    engine.apply(config(caffeine: true, caps: .hyper))
    expect(!engine.caffeineOn, "same caffeineOnLaunch value leaves the toggled state alone")
    expectEqual(ports.count("acquire"), 1)

    // Changing the setting while running sets the state to the new value.
    engine.apply(config(caffeine: false, caps: .hyper))
    expect(!engine.caffeineOn, "false while already off: nothing to release")
    expectEqual(ports.count("release"), 1)
    engine.apply(config(caffeine: true, caps: .hyper))
    expect(engine.caffeineOn, "changed to true acquires")
    expectEqual(ports.count("acquire"), 2)
    engine.apply(config(caffeine: false, caps: .hyper))
    expect(!engine.caffeineOn, "changed to false releases")
    expectEqual(ports.count("release"), 2)

    // Toggle back on.
    engine.toggleCaffeine()
    expect(engine.caffeineOn, "toggle turns it on again")
    expectEqual(ports.count("acquire"), 3)

    // A failed acquire leaves caffeine off and is retried by the next toggle.
    let (failing, failPorts) = makeEngine()
    failPorts.acquireResult = false
    failing.apply(config(caffeine: true))
    expect(!failing.caffeineOn, "failed acquire leaves caffeineOn false")
    failing.toggleCaffeine()
    expectEqual(failPorts.count("acquire"), 2)
    expect(!failing.caffeineOn, "still off")
    expectEqual(failPorts.count("release"), 0)
}

// MARK: - Thumb diversion

private func thumbTests() {
    let (engine, ports) = makeEngine()
    engine.apply(config())
    expectEqual(ports.calls.filter { $0.hasPrefix("thumb:") }, ["thumb:false"])
    engine.apply(config(caps: .meh))
    expectEqual(ports.count(prefix: "thumb:"), 1)

    engine.apply(config(thumb: thumbAction))
    expectEqual(ports.calls.filter { $0.hasPrefix("thumb:") }, ["thumb:false", "thumb:true"])
    // Changing the thumb action keeps it enabled: no second divert.
    engine.apply(config(thumb: .shell("other")))
    expectEqual(ports.count(prefix: "thumb:"), 2)
    engine.thumbPressed()
    expectEqual(ports.ran, [.shell("other")])

    engine.apply(config())
    expectEqual(ports.calls.filter { $0.hasPrefix("thumb:") }, ["thumb:false", "thumb:true", "thumb:false"])
    engine.thumbPressed()
    expectEqual(ports.ran, [.shell("other")])
}

// MARK: - Login item

private func loginItemTests() {
    let cases: [(login: Bool, status: LoginItemStatus, expected: [String])] = [
        (true, .notRegistered, ["login:true"]),
        (true, .notFound, ["login:true"]),
        (true, .enabled, []),
        (true, .requiresApproval, []),
        (false, .enabled, ["login:false"]),
        (false, .requiresApproval, ["login:false"]),
        (false, .notRegistered, []),
        (false, .notFound, []),
    ]
    for c in cases {
        let (engine, ports) = makeEngine()
        ports.loginStatus = c.status
        engine.apply(config(login: c.login))
        expect(ports.calls.filter { $0.hasPrefix("login:") } == c.expected, "login=\(c.login) status=\(c.status)")
        expectEqual(ports.errors, [])
    }

    let (engine, ports) = makeEngine()
    ports.loginError = "denied by user"
    engine.apply(config(login: true))
    expectEqual(ports.errors, ["launch at login failed: denied by user"])
    // Re-evaluated on every apply, so a transient failure is retried on the next reload.
    engine.apply(config(login: true))
    expectEqual(ports.count("login:true"), 2)
}

// MARK: - Tap lifecycle

private func tapLifecycleTests() {
    // Trusted with nothing to observe: no tap.
    var (engine, ports) = makeEngine()
    engine.apply(config())
    expectEqual(ports.count(prefix: "install:"), 0)
    expectEqual(ports.count("removeTap"), 0)

    // Mask needed: install once; repeated syncs and equivalent applies keep it.
    engine.apply(config(caps: .meh))
    expectEqual(ports.calls.filter { $0.hasPrefix("install:") }, ["install:\(String(keyBits, radix: 16))"])
    engine.sync()
    engine.apply(config(caps: .hyper))
    expectEqual(ports.count(prefix: "install:"), 1)

    // A changed mask re-installs (replace semantics: no removeTap in between).
    engine.apply(config(caps: .hyper, back: backAction))
    expectEqual(ports.count(prefix: "install:"), 2)
    expectEqual(ports.calls.last(where: { $0.hasPrefix("install:") }), "install:\(String(keyBits | mouseBits, radix: 16))")
    engine.apply(config(caps: .hyper, back: backAction, vertical: true))
    expectEqual(ports.calls.last(where: { $0.hasPrefix("install:") }), "install:\(String(keyBits | mouseBits | scrollBit, radix: 16))")
    expectEqual(ports.count("removeTap"), 0)

    // No longer needed: removed.
    engine.apply(config())
    expectEqual(ports.count("removeTap"), 1)
    engine.sync()
    expectEqual(ports.count("removeTap"), 1)

    // Logged creation and teardown.
    expect(ports.logs.contains("tap created location=session mask=\(String(keyBits, radix: 16)) ok=true"), "creation logged")
    expect(ports.logs.contains("tap torn down location=session"), "teardown logged")
    expect(ports.debugLines.contains("tap torn down location=session"), "teardown in debug log")

    // Install failure: logged, and every following sync retries until it works.
    (engine, ports) = makeEngine()
    ports.installResult = false
    engine.apply(config(caps: .meh))
    expectEqual(ports.errors, ["event tap could not be created"])
    expect(ports.logs.contains("tap created location=session mask=\(String(keyBits, radix: 16)) ok=false"), "failure logged")
    engine.sync()
    expectEqual(ports.count(prefix: "install:"), 2)
    ports.installResult = true
    engine.sync()
    expectEqual(ports.count(prefix: "install:"), 3)
    engine.sync()
    expectEqual(ports.count(prefix: "install:"), 3)
    expectEqual(ports.count("removeTap"), 0)

    // Losing Accessibility trust removes the tap; regaining it brings it back.
    (engine, ports) = makeEngine()
    engine.apply(config(caps: .meh))
    ports.trusted = false
    engine.sync()
    expectEqual(ports.count("removeTap"), 1)
    engine.sync()
    expectEqual(ports.count("removeTap"), 1)
    expectEqual(ports.count(prefix: "install:"), 1)
    ports.trusted = true
    engine.sync()
    expectEqual(ports.count(prefix: "install:"), 2)

    // Never trusted: nothing is installed at all.
    (engine, ports) = makeEngine()
    ports.trusted = false
    engine.apply(config(caps: .meh, back: backAction))
    expectEqual(ports.count(prefix: "install:"), 0)
    expectEqual(ports.count("removeTap"), 0)

    // Trust changes are logged once per change.
    (engine, ports) = makeEngine()
    engine.apply(config())
    engine.sync()
    expectEqual(ports.logs.filter { $0.hasPrefix("trust changed") }, ["trust changed trusted=true"])
    ports.trusted = false
    engine.sync()
    engine.sync()
    expectEqual(ports.logs.filter { $0.hasPrefix("trust changed") }, ["trust changed trusted=true", "trust changed trusted=false"])
    expectEqual(ports.debugLines.filter { $0.hasPrefix("trust changed") }.count, 2)
}

// MARK: - Caps monitoring

private func capsMonitoringTests() {
    func lastCaps(_ ports: FakePorts) -> String? { ports.calls.last(where: { $0.hasPrefix("caps:") }) }

    var (engine, ports) = makeEngine()
    engine.apply(config(caps: .default))
    expectEqual(lastCaps(ports), "caps:false")
    engine.apply(config(caps: .meh))
    expectEqual(lastCaps(ports), "caps:true")
    engine.apply(config(caps: .hyper))
    expectEqual(lastCaps(ports), "caps:true")
    engine.apply(config(caps: .default, back: backAction))
    expectEqual(lastCaps(ports), "caps:false")

    // Modifier mode but the tap is not live (untrusted, or the tap failed): monitoring stays off.
    (engine, ports) = makeEngine()
    ports.trusted = false
    engine.apply(config(caps: .meh))
    expectEqual(lastCaps(ports), "caps:false")
    ports.trusted = true
    engine.sync()
    expectEqual(lastCaps(ports), "caps:true")
    ports.trusted = false
    engine.sync()
    expectEqual(lastCaps(ports), "caps:false")

    (engine, ports) = makeEngine()
    ports.installResult = false
    engine.apply(config(caps: .meh))
    expectEqual(lastCaps(ports), "caps:false")

    // Every sync tells the platform (it applies its own idempotence).
    (engine, ports) = makeEngine()
    engine.apply(config(caps: .meh))
    engine.sync()
    engine.sync()
    expectEqual(ports.count("caps:true"), 3)
}

// MARK: - Swallowed buttons and the mask

private func swallowedButtonTests() {
    let down = TapEvent(type: .otherMouseDown, button: 3)
    let up = TapEvent(type: .otherMouseUp, button: 3)

    // The mapping is removed while the button is held: the tap stays until the up was swallowed.
    var (engine, ports) = makeEngine()
    engine.apply(config(back: backAction))
    expectEqual(engine.handleTapEvent(down), TapDecision(pass: false))
    engine.apply(config())
    expectEqual(ports.count("removeTap"), 0)
    expectEqual(ports.calls.last(where: { $0.hasPrefix("install:") }), "install:\(String(mouseBits, radix: 16))")
    expectEqual(engine.handleTapEvent(up), TapDecision(pass: false))
    engine.sync()
    expectEqual(ports.count("removeTap"), 1)

    // Without Accessibility trust no up can arrive: the record is dropped, so regaining trust does not reinstall.
    (engine, ports) = makeEngine()
    engine.apply(config(back: backAction))
    _ = engine.handleTapEvent(down)
    engine.apply(config())
    ports.trusted = false
    engine.sync()
    expectEqual(ports.count("removeTap"), 1)
    ports.trusted = true
    engine.sync()
    expectEqual(ports.count(prefix: "install:"), 1)
}

// MARK: - Caps key paths

private func capsEventTests() {
    // Short tap sends Esc once; the same press with a typed key does not.
    var (engine, ports) = makeEngine()
    engine.apply(config(caps: .meh))
    engine.capsKeyChanged(down: true, nowNanos: 0)
    engine.capsKeyChanged(down: false, nowNanos: 50 * ms)
    expectEqual(ports.count("escape"), 1)
    expect(ports.logs.contains("caps down") && ports.logs.contains("caps up held_ms=50 esc=true"), "caps transitions logged")
    expect(ports.debugLines.contains("caps down") && ports.debugLines.contains("caps up held_ms=50 esc=true"), "caps transitions in debug log")

    engine.capsKeyChanged(down: true, nowNanos: 100 * ms)
    expectEqual(engine.handleTapEvent(TapEvent(type: .keyDown, keyCode: 40)).flags, Optional(CGEventFlags([.maskControl, .maskAlternate, .maskCommand])))
    engine.capsKeyChanged(down: false, nowNanos: 120 * ms)
    expectEqual(ports.count("escape"), 1)

    // A mode change while Caps is held ends the hold: the release sends no Esc and keys get no flags.
    (engine, ports) = makeEngine()
    engine.apply(config(caps: .meh))
    engine.capsKeyChanged(down: true, nowNanos: 0)
    engine.apply(config(caps: .hyper))
    expectEqual(engine.handleTapEvent(TapEvent(type: .keyDown, keyCode: 40)), TapDecision())
    engine.capsKeyChanged(down: false, nowNanos: 10 * ms)
    expectEqual(ports.count("escape"), 0)

    // Other config changes keep the hold.
    engine.capsKeyChanged(down: true, nowNanos: 100 * ms)
    engine.apply(config(caps: .hyper, thumb: thumbAction))
    engine.capsKeyChanged(down: false, nowNanos: 110 * ms)
    expectEqual(ports.count("escape"), 1)

    // Removing the keyboard ends the hold without Esc.
    (engine, ports) = makeEngine()
    engine.apply(config(caps: .meh))
    engine.capsKeyChanged(down: true, nowNanos: 0)
    engine.capsKeyboardRemoved()
    expectEqual(ports.debugLines.last, "caps hid device removed")
    engine.capsKeyChanged(down: false, nowNanos: 10 * ms)
    expectEqual(ports.count("escape"), 0)

    // Switching to default (monitor off) also ends the hold.
    (engine, ports) = makeEngine()
    engine.apply(config(caps: .meh))
    engine.capsKeyChanged(down: true, nowNanos: 0)
    engine.apply(config(caps: .default))
    engine.capsKeyChanged(down: false, nowNanos: 10 * ms)
    expectEqual(ports.count("escape"), 0)

    // Losing the tap while held (trust revoked) ends the hold.
    (engine, ports) = makeEngine()
    engine.apply(config(caps: .meh))
    engine.capsKeyChanged(down: true, nowNanos: 0)
    ports.trusted = false
    engine.sync()
    engine.capsKeyChanged(down: false, nowNanos: 10 * ms)
    expectEqual(ports.count("escape"), 0)

    // Replacing the tap (mask change) ends the hold too.
    (engine, ports) = makeEngine()
    engine.apply(config(caps: .meh))
    engine.capsKeyChanged(down: true, nowNanos: 0)
    engine.apply(config(caps: .meh, back: backAction))
    expectEqual(ports.count(prefix: "install:"), 2)
    engine.capsKeyChanged(down: false, nowNanos: 10 * ms)
    expectEqual(ports.count("escape"), 0)
}

// MARK: - Tap events

private func tapEventTests() {
    let (engine, ports) = makeEngine()
    engine.apply(config(back: backAction, vertical: true))

    // Mapped side button: swallowed, action run through the ports.
    expectEqual(engine.handleTapEvent(TapEvent(type: .otherMouseDown, button: 3)), TapDecision(pass: false))
    expectEqual(ports.ran, [backAction])
    // Unmapped forward button passes, nothing runs.
    expectEqual(engine.handleTapEvent(TapEvent(type: .otherMouseDown, button: 4)), TapDecision())
    expectEqual(ports.ran, [backAction])

    // Scroll: the decision carries the negated axis.
    let wheel = TapEvent(type: .scrollWheel, vertical: ScrollAxis(line: 1, fixed: 1, point: 8))
    expectEqual(engine.handleTapEvent(wheel).vertical, ScrollAxis(line: -1, fixed: -1, point: -8))

    // Tap disabled: log effects reach the ports and the tap is asked to re-enable.
    let disabled = engine.handleTapEvent(TapEvent(type: .tapDisabledByTimeout))
    expectEqual(disabled, TapDecision(pass: true, reenableTap: true))
    expect(ports.logs.contains("tap disabled reason=timeout capsHeld=false"), "disable logged")
    expect(ports.debugLines.contains("tap disabled reason=timeout capsHeld=false"), "disable in debug log")
}

// MARK: - State change notification

private func stateChangeTests() {
    let (engine, _) = makeEngine()
    var notifications = 0
    engine.onStateChange = { notifications += 1 }
    engine.apply(config())
    expectEqual(notifications, 1)
    engine.sync()
    expectEqual(notifications, 2)
    engine.toggleCaffeine()
    expectEqual(notifications, 3)
    expect(engine.caffeineOn, "toggle from default (off) turns caffeine on")
}

// MARK: - Shutdown

private func shutdownTests() {
    let (engine, ports) = makeEngine()
    engine.apply(config(caffeine: true, caps: .meh, thumb: thumbAction))
    expect(engine.caffeineOn, "precondition: caffeine on")
    ports.clear()

    engine.shutdown()
    expectEqual(ports.calls, ["release", "caps:false", "removeTap", "shutdownThumb"])
    expect(!engine.caffeineOn, "caffeine released")
    expectEqual(engine.settings, TapSettings())
    engine.thumbPressed()
    expectEqual(ports.ran, [])
    expect(ports.logs.contains("tap torn down location=session"), "teardown logged")

    // A late timer tick after shutdown does not bring the tap back.
    ports.clear()
    engine.sync()
    expectEqual(ports.count(prefix: "install:"), 0)
    expectEqual(ports.count("removeTap"), 0)

    // Safe twice: nothing left to release or remove.
    ports.clear()
    engine.shutdown()
    expectEqual(ports.calls, ["caps:false", "shutdownThumb"])

    // Shutdown without ever applying a config.
    let (fresh, freshPorts) = makeEngine()
    fresh.shutdown()
    expectEqual(freshPorts.calls, ["caps:false", "shutdownThumb"])
}

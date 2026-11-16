@testable import HyperMugCore

// The controller is driven like the Platform adapter drives it: device events and results go in, commands come out.
// `now` is an injected monotonic clock in seconds. Reports are written out as raw bytes, not built with the codec.

private let mouse = ThumbDeviceInfo(name: "MX Master 3S B", transport: "Bluetooth Low Energy", productID: 0xB035,
                                    primaryUsagePage: 1, primaryUsage: 2)
private let keyboard = ThumbDeviceInfo(name: "MX Keys", transport: "Bluetooth Low Energy", productID: 0xB35B,
                                       primaryUsagePage: 1, primaryUsage: 6)
private let mouseName = "MX Master 3S B"
private let reprogIndex: UInt8 = 9
private let wdsIndex: UInt8 = 0x0C
private let deniedText = "Input Monitoring denied — enable HyperMug in System Settings › Privacy & Security › Input Monitoring"

private func frame(_ head: [UInt8]) -> [UInt8] {
    head + [UInt8](repeating: 0, count: 20 - head.count)
}

/// A reply to one of our requests (software ID 0xA).
private func reply(_ featureIndex: UInt8, function: UInt8 = 0, _ params: [UInt8]) -> [UInt8] {
    frame([0x11, 0xFF, featureIndex, function << 4 | 0x0A] + params)
}

/// An unsolicited notification (software ID 0).
private func notification(_ featureIndex: UInt8, function: UInt8 = 0, _ params: [UInt8]) -> [UInt8] {
    frame([0x11, 0xFF, featureIndex, function << 4] + params)
}

private func errorReply(featureIndex: UInt8, function: UInt8, code: UInt8) -> [UInt8] {
    frame([0x11, 0xFF, 0xFF, featureIndex, function << 4 | 0x0A, code])
}

private let getReprog = frame([0x11, 0xFF, 0x00, 0x0A, 0x1B, 0x04])
private let getWds = frame([0x11, 0xFF, 0x00, 0x0A, 0x1D, 0x4B])
private let divertBytes = frame([0x11, 0xFF, reprogIndex, 0x3A, 0x00, 0xC3, 0x03])
private let undivertBytes = frame([0x11, 0xFF, reprogIndex, 0x3A, 0x00, 0xC3, 0x02])
private let divertEcho = reply(reprogIndex, function: 3, [0x00, 0xC3, 0x03])
private let thumbDown = notification(reprogIndex, [0x00, 0xC3])
private let thumbUp = notification(reprogIndex, [])

/// A write command; the payload with the report ID byte is tried first unless `withID` is false.
private func write(_ id: HIDDeviceID, _ bytes: [UInt8], withID: Bool = true) -> ThumbCommand {
    let withoutID = Array(bytes.dropFirst())
    return .write(id, payloads: withID ? [bytes, withoutID] : [withoutID, bytes])
}

private func nonLog(_ commands: [ThumbCommand]) -> [ThumbCommand] {
    commands.filter { if case .log = $0 { return false } else { return true } }
}

private func feed(_ c: inout ThumbController, _ id: HIDDeviceID, _ bytes: [UInt8], now: Double = 0) -> [ThumbCommand] {
    c.received(id, reportID: 0x11, bytes: bytes, now: now)
}

/// Feeds a report to device 1.
private func feed(_ c: inout ThumbController, _ bytes: [UInt8], now: Double = 0) -> [ThumbCommand] {
    feed(&c, 1, bytes, now: now)
}

private enum Progress: Int { case opened = 1, reprogKnown, wdsKnown, diverted }

/// An enabled controller with one granted, open mouse (id `id`) that went through the lookup/divert steps up to `progress`.
private func controller(upTo progress: Progress, id: HIDDeviceID = 1, now: Double = 0) -> ThumbController {
    var c = ThumbController()
    _ = c.setEnabled(true, access: .granted, now: now)
    _ = c.deviceMatched(id, mouse, access: .granted, now: now)
    _ = c.openFinished(id, code: 0, now: now)
    if progress.rawValue >= Progress.reprogKnown.rawValue { _ = feed(&c, id, reply(0, [reprogIndex, 0, 4]), now: now) }
    if progress.rawValue >= Progress.wdsKnown.rawValue { _ = feed(&c, id, reply(0, [wdsIndex, 0, 1]), now: now) }
    if progress.rawValue >= Progress.diverted.rawValue { _ = feed(&c, id, divertEcho, now: now) }
    return c
}

func thumbControllerTests() {
    thumbMatchingTests()
    thumbPermissionTests()
    thumbOpenTests()
    thumbDivertFlowTests()
    thumbLookupFailureTests()
    thumbUnexpectedReplyTests()
    thumbEventTests()
    thumbReconfigurationTests()
    thumbTickTests()
    thumbWriteResultTests()
    thumbDisableTests()
    thumbRemovalTests()
    thumbShutdownTests()
    thumbMultiDeviceTests()
}

// MARK: Matching

private func thumbMatchingTests() {
    var c = ThumbController()

    // Only mice count: CID 0x00C3 is a different key on Logitech keyboards.
    expectEqual(c.deviceMatched(1, keyboard, access: .granted, now: 0),
                [.log(.info, "skipped MX Keys: not a mouse (primary usage 1:6)")], "keyboard skipped")
    expectEqual(c.deviceMatched(2, ThumbDeviceInfo(), access: .granted, now: 0),
                [.log(.info, "skipped unknown device: not a mouse (primary usage -1:-1)")], "no properties at all")
    expectEqual(c.deviceMatched(3, ThumbDeviceInfo(name: "Half", primaryUsagePage: 1), access: .granted, now: 0),
                [.log(.info, "skipped Half: not a mouse (primary usage 1:-1)")], "usage missing")
    expectEqual(c.deviceMatched(4, ThumbDeviceInfo(name: "Pad", primaryUsagePage: 0x0D, primaryUsage: 2), access: .granted, now: 0),
                [.log(.info, "skipped Pad: not a mouse (primary usage 13:2)")], "right usage on the wrong page")
    expectEqual(c.setEnabled(true, access: .granted, now: 0), [], "skipped devices never get a session")
    expectEqual(c.setEnabled(false, access: .granted, now: 0), [])

    // A mouse is remembered while disabled, and its duplicate announcement is ignored.
    expectEqual(c.deviceMatched(5, mouse, access: .granted, now: 0),
                [.log(.info, "matched MX Master 3S B (PID 0xB035, transport Bluetooth Low Energy)")], "match while disabled only logs")
    expectEqual(c.deviceMatched(5, mouse, access: .granted, now: 0), [], "duplicate id ignored")
    expectEqual(c.tick(access: .granted, now: 2), [], "a disabled controller does not open anything on tick")

    // Missing name/transport/product ID fall back to readable placeholders.
    let bare = ThumbDeviceInfo(primaryUsagePage: 1, primaryUsage: 2)
    expectEqual(c.deviceMatched(6, bare, access: .granted, now: 0),
                [.log(.info, "matched unknown device (PID 0x0000, transport unknown)")], "placeholders")

    // Enabling opens every remembered mouse; a mouse matched afterwards opens at once.
    expectEqual(c.setEnabled(true, access: .granted, now: 0), [.open(5), .open(6)], "enable opens all sessions")
    expect(c.enabled, "enabled")
    let late = c.deviceMatched(7, mouse, access: .granted, now: 0)
    expectEqual(nonLog(late), [.open(7)], "match while enabled and permitted opens")
}

// MARK: Permission

private func thumbPermissionTests() {
    // The system prompt is requested once; its answer decides what happens next.
    var c = ThumbController()
    expectEqual(c.setEnabled(true, access: .unknown, now: 0), [], "no sessions yet")
    let first = c.deviceMatched(1, mouse, access: .unknown, now: 0)
    expectEqual(first, [.log(.info, "matched MX Master 3S B (PID 0xB035, transport Bluetooth Low Energy)"),
                        .log(.info, "Input Monitoring is unknown; requesting access"),
                        .requestAccess], "first unpermitted open requests access")
    expectEqual(nonLog(c.deviceMatched(2, mouse, access: .unknown, now: 0)), [], "no second request while the prompt is up")
    expectEqual(c.tick(access: .unknown, now: 2), [], "tick stays quiet while the prompt is up")

    expectEqual(c.accessRequestFinished(granted: false, now: 3), [.log(.error, deniedText)], "denial is logged")
    expectEqual(c.accessRequestFinished(granted: false, now: 3), [], "and only once")
    expectEqual(c.tick(access: .denied, now: 4), [], "tick after the denial is quiet")
    expectEqual(c.tick(access: .denied, now: 6), [], "still quiet")

    // Granting in System Settings is noticed by the next tick: every closed session opens.
    expectEqual(c.tick(access: .granted, now: 8), [.open(1), .open(2)], "access granted later opens the sessions")
    // Revoked again: the denial is reported once more (not once per session).
    expectEqual(c.tick(access: .denied, now: 10), [.log(.error, deniedText)], "a new denial is logged once")

    // A denied state gets the same single request.
    var d = ThumbController()
    _ = d.setEnabled(true, access: .denied, now: 0)
    expectEqual(d.deviceMatched(1, mouse, access: .denied, now: 0),
                [.log(.info, "matched MX Master 3S B (PID 0xB035, transport Bluetooth Low Energy)"),
                 .log(.info, "Input Monitoring is denied; requesting access"), .requestAccess])
    expectEqual(nonLog(d.deviceMatched(2, mouse, access: .denied, now: 0)), [], "no second request")

    // The prompt is answered "granted" while enabled: open everything that is closed.
    var g = ThumbController()
    _ = g.setEnabled(true, access: .unknown, now: 0)
    _ = g.deviceMatched(1, mouse, access: .unknown, now: 0)
    _ = g.deviceMatched(2, mouse, access: .unknown, now: 0)
    expectEqual(g.accessRequestFinished(granted: true, now: 1),
                [.log(.info, "Input Monitoring granted"), .open(1), .open(2)], "granted answer opens the sessions")

    // Sessions that are already open are not opened again when the answer arrives for a newer mouse.
    var h = ThumbController()
    _ = h.setEnabled(true, access: .granted, now: 0)
    _ = h.deviceMatched(1, mouse, access: .granted, now: 0)
    _ = h.openFinished(1, code: 0, now: 0)
    _ = h.deviceMatched(2, mouse, access: .denied, now: 0)      // permission was revoked meanwhile → prompt
    expectEqual(h.accessRequestFinished(granted: true, now: 1), [.log(.info, "Input Monitoring granted"), .open(2)],
                "only the closed session opens")

    // Answered "granted" after the feature was switched off meanwhile: nothing to open.
    var off = ThumbController()
    _ = off.setEnabled(true, access: .unknown, now: 0)
    _ = off.deviceMatched(1, mouse, access: .unknown, now: 0)
    _ = off.setEnabled(false, access: .unknown, now: 1)
    expectEqual(off.accessRequestFinished(granted: true, now: 2), [.log(.info, "Input Monitoring granted")],
                "nothing opens while disabled")
}

// MARK: Opening

private func thumbOpenTests() {
    var c = ThumbController()
    _ = c.setEnabled(true, access: .granted, now: 0)
    _ = c.deviceMatched(1, mouse, access: .granted, now: 0)

    // Failures are reported once per distinct code.
    let notPermitted: UInt32 = 0xE00002E2
    let relaunch = ThumbCommand.log(.error,
        "opening MX Master 3S B not permitted (0xE00002E2); relaunch HyperMug after granting Input Monitoring")
    expectEqual(c.openFinished(1, code: notPermitted, now: 0), [relaunch], "not permitted → relaunch hint")
    expectEqual(c.openFinished(1, code: notPermitted, now: 0), [], "same code again is quiet")
    expectEqual(c.openFinished(1, code: 0xE00002C5, now: 0), [.log(.error, "opening MX Master 3S B failed (0xE00002C5)")],
                "another code is reported")
    expectEqual(c.openFinished(1, code: notPermitted, now: 0), [relaunch], "going back to the first code is a change")

    // The failed session stays closed; each tick retries.
    expectEqual(c.tick(access: .granted, now: 2), [.open(1)], "tick retries the open")

    // Success starts the feature lookup.
    expectEqual(c.openFinished(1, code: 0, now: 5),
                [.log(.info, "opened MX Master 3S B; looking up feature 0x1B04"), write(1, getReprog)], "success looks up 0x1B04")
    expectEqual(c.tick(access: .granted, now: 5), [], "an open session is not opened again")

    // Success clears the failure memory: after a close/reopen the same failure is reported again.
    _ = c.setEnabled(false, access: .granted, now: 6)
    expectEqual(c.setEnabled(true, access: .granted, now: 7), [.open(1)])
    expectEqual(c.openFinished(1, code: notPermitted, now: 7), [relaunch], "failure memory was reset by the success")

    expectEqual(c.openFinished(99, code: 0, now: 8), [], "unknown device ignored")
}

// MARK: Lookup and divert

private func thumbDivertFlowTests() {
    var c = ThumbController()
    _ = c.setEnabled(true, access: .granted, now: 0)
    _ = c.deviceMatched(1, mouse, access: .granted, now: 0)
    _ = c.openFinished(1, code: 0, now: 0)

    // 0x1B04 lookup → 0x1D4B lookup → divert → echo. The reply to the second reply also arrives without the ID byte.
    expectEqual(feed(&c, reply(0, [reprogIndex, 0, 4])),
                [.log(.info, "MX Master 3S B: 0x1B04 @ index 9"), write(1, getWds)], "reprog index found")
    expectEqual(c.received(1, reportID: 0x11, bytes: Array(reply(0, [wdsIndex, 0, 1]).dropFirst()), now: 0),
                [.log(.info, "MX Master 3S B: 0x1D4B @ index 12"), write(1, divertBytes)], "wds index found → divert")
    expectEqual(feed(&c, divertEcho),
                [.log(.info, "diverted CID 0x00C3 on MX Master 3S B (0x1B04 @ index 9)")], "echo → diverted")
    expectEqual(c.tick(access: .granted, now: 100), [], "a diverted session needs no further requests")

    // The late duplicate of the first lookup reply must not be taken for the 0x1D4B answer.
    var d = controller(upTo: .reprogKnown)
    expectEqual(feed(&d, reply(0, [reprogIndex, 0, 4])), [], "duplicate lookup reply ignored")
    expectEqual(nonLog(feed(&d, reply(0, [wdsIndex, 0, 1]))), [write(1, divertBytes)], "the real answer still works")

    // A device without 0x1D4B is diverted all the same, with one log line less.
    var e = controller(upTo: .reprogKnown)
    expectEqual(feed(&e, reply(0, [0, 0, 0])), [write(1, divertBytes)], "no wireless-status feature")
    expectEqual(feed(&e, divertEcho), [.log(.info, "diverted CID 0x00C3 on MX Master 3S B (0x1B04 @ index 9)")])
}

private func thumbLookupFailureTests() {
    // No 0x1B04 feature: unsupported, device released, and left alone (also by tick).
    var a = controller(upTo: .opened)
    expectEqual(feed(&a, reply(0, [0, 0, 0])),
                [.log(.error, "MX Master 3S B has no feature 0x1B04; thumb button unsupported"), .close(1)])
    expectEqual(a.tick(access: .granted, now: 10), [], "unsupported is not retried")
    expectEqual(feed(&a, notification(0, [0x00, 0xC3])), [], "an unsupported session reports no button")
    expectEqual(a.setEnabled(false, access: .granted, now: 11), [], "nothing to undo for an unsupported device")
    expectEqual(a.setEnabled(true, access: .granted, now: 12), [.open(1)], "toggling the feature retries")

    // An error reply to the 0x1B04 lookup: failed, device released, not retried.
    var b = controller(upTo: .opened)
    expectEqual(feed(&b, errorReply(featureIndex: 0, function: 0, code: 0x0B)),
                [.log(.error, "HID++ error 0xb from MX Master 3S B (feature index 0, function 0)"), .close(1)])
    expectEqual(b.tick(access: .granted, now: 10), [], "failed is not retried")
    expectEqual(feed(&b, notification(0, [0x00, 0xC3])), [], "a failed session reports no button")

    // An error to the optional 0x1D4B lookup does not stop the divert.
    var c = controller(upTo: .reprogKnown)
    expectEqual(feed(&c, errorReply(featureIndex: 0, function: 0, code: 2)),
                [.log(.error, "HID++ error 0x2 from MX Master 3S B (feature index 0, function 0)"), write(1, divertBytes)])
    expectEqual(feed(&c, divertEcho), [.log(.info, "diverted CID 0x00C3 on MX Master 3S B (0x1B04 @ index 9)")])

    // The divert itself rejected (CID absent): unsupported, released without an undivert write.
    var d = controller(upTo: .wdsKnown)
    let rejected = feed(&d, errorReply(featureIndex: reprogIndex, function: 3, code: 2))
    expectEqual(rejected, [.log(.error, "HID++ error 0x2 from MX Master 3S B (feature index 9, function 3)"),
                           .log(.error, "MX Master 3S B rejected diverting CID 0x00C3; thumb button unsupported"),
                           .close(1)])
    expectEqual(d.tick(access: .granted, now: 10), [], "unsupported is not retried")
}

private func thumbUnexpectedReplyTests() {
    var c = controller(upTo: .opened)    // waiting for the 0x1B04 lookup: feature index 0, function 0
    expectEqual(feed(&c, reply(5, [reprogIndex])), [], "reply for another feature index")
    expectEqual(feed(&c, reply(0, function: 1, [reprogIndex])), [], "reply for another function")
    expectEqual(feed(&c, errorReply(featureIndex: 5, function: 0, code: 2)), [], "error for another feature index")
    expectEqual(feed(&c, errorReply(featureIndex: 0, function: 1, code: 2)), [], "error for another function")
    expectEqual(feed(&c, frame([0x11, 0xFF, 0x00, 0x0B, reprogIndex])), [], "reply to somebody else's request")
    expectEqual(feed(&c, frame([0x11, 0xFF, 0xFF, 0x00, 0x0B, 0x02])), [], "error to somebody else's request")
    expectEqual(nonLog(feed(&c, reply(0, [reprogIndex, 0, 4]))), [write(1, getWds)], "the matching reply is still accepted")

    // A diverted session has no request in flight: replies and errors are noise.
    var d = controller(upTo: .diverted)
    expectEqual(feed(&d, divertEcho), [], "second echo ignored")
    expectEqual(feed(&d, errorReply(featureIndex: reprogIndex, function: 3, code: 2)), [], "stray error ignored")
    expectEqual(feed(&d, thumbDown), [.press], "still diverted afterwards")

    // Not a HID++ long report at all, or a device we do not know.
    var e = controller(upTo: .diverted)
    expectEqual(e.received(1, reportID: 0x02, bytes: [0x02, 0x00, 0x01, 0x00, 0x00], now: 0), [], "mouse report")
    expectEqual(e.received(99, reportID: 0x11, bytes: thumbDown, now: 0), [], "unknown device")
}

// MARK: Events

private func thumbEventTests() {
    var c = controller(upTo: .diverted)
    expectEqual(feed(&c, thumbDown), [.press], "press")
    expectEqual(feed(&c, thumbDown), [], "still held: no second press")
    expectEqual(feed(&c, thumbUp), [], "release does nothing")
    expectEqual(feed(&c, thumbDown), [.press], "next press")
    _ = feed(&c, thumbUp)
    expectEqual(feed(&c, notification(reprogIndex, [0x00, 0x56])), [], "another button alone")
    expectEqual(feed(&c, notification(reprogIndex, [0x00, 0x56, 0x00, 0xC3])), [.press], "thumb pressed while another is held")
    expectEqual(feed(&c, notification(5, [0x00, 0xC3])), [], "notification of another feature")
    expectEqual(feed(&c, notification(reprogIndex, function: 1, [0x00, 0xC3])), [], "other event function")

    // The press counts once the divert request is out, even before its echo arrives.
    var d = controller(upTo: .wdsKnown)
    expectEqual(feed(&d, thumbDown), [.press], "press while the divert is being confirmed")
    _ = feed(&d, divertEcho)
    expectEqual(feed(&d, thumbDown), [], "the held state survives the echo")

    // Events before the divert request are not button presses.
    var e = controller(upTo: .opened)
    expectEqual(feed(&e, notification(0, [0x00, 0xC3])), [], "no feature index known yet")
    var f = controller(upTo: .reprogKnown)
    expectEqual(feed(&f, thumbDown), [], "reprog known but divert not sent yet")

    // A closed session reports nothing, and a re-opened one starts with nothing held.
    var g = controller(upTo: .diverted)
    _ = feed(&g, thumbDown)
    _ = g.setEnabled(false, access: .granted, now: 1)
    expectEqual(feed(&g, thumbUp), [], "late report for a closed session")
    _ = g.setEnabled(true, access: .granted, now: 2)
    _ = g.openFinished(1, code: 0, now: 2)
    _ = feed(&g, reply(0, [reprogIndex, 0, 4]), now: 2)
    _ = feed(&g, reply(0, [wdsIndex, 0, 1]), now: 2)
    _ = feed(&g, divertEcho, now: 2)
    expectEqual(feed(&g, thumbDown), [.press], "held state was reset by the close")
}

private func thumbReconfigurationTests() {
    let wake = notification(wdsIndex, [0x00, 0x01])

    // The device asks to be configured again (after sleep): divert again, and confirm it.
    var c = controller(upTo: .diverted)
    expectEqual(feed(&c, wake), [.log(.info, "MX Master 3S B asked for reconfiguration; diverting again"), write(1, divertBytes)])
    expectEqual(feed(&c, wake), [], "a second request while diverting is ignored")
    expectEqual(feed(&c, divertEcho), [.log(.info, "diverted CID 0x00C3 on MX Master 3S B (0x1B04 @ index 9)")])
    expectEqual(feed(&c, notification(wdsIndex, [0x00, 0x00])), [], "other wireless-status notifications are ignored")

    // Not diverted yet (waiting for the echo): nothing to re-apply.
    var d = controller(upTo: .wdsKnown)
    expectEqual(feed(&d, wake), [], "ignored before the first divert is confirmed")

    // A device without 0x1D4B: index 0 is the root feature, whose events must not be mistaken for it.
    var e = controller(upTo: .reprogKnown)
    _ = feed(&e, reply(0, [0, 0, 0]))
    _ = feed(&e, divertEcho)
    expectEqual(feed(&e, notification(0, [0x00, 0x01])), [], "root feature notification")
}

// MARK: tick

private func thumbTickTests() {
    // A request without reply is resent after more than 1.5 s, three attempts in total, then given up.
    var c = controller(upTo: .opened, now: 0)
    expectEqual(c.tick(access: .granted, now: 1.5), [], "exactly the timeout is not enough")
    expectEqual(c.tick(access: .granted, now: 1.6),
                [.log(.info, "resending HID++ request to MX Master 3S B (attempt 2)"), write(1, getReprog)], "second attempt")
    expectEqual(c.tick(access: .granted, now: 3.0), [], "the timeout restarts at the resend")
    expectEqual(c.tick(access: .granted, now: 3.2),
                [.log(.info, "resending HID++ request to MX Master 3S B (attempt 3)"), write(1, getReprog)], "third attempt")
    expectEqual(c.tick(access: .granted, now: 4.8),
                [.log(.error, "no HID++ reply from MX Master 3S B after 3 attempts; giving up until reconnect or re-enable"),
                 .close(1)], "gave up; nothing to undivert yet")
    expectEqual(c.tick(access: .granted, now: 10), [], "failed sessions are left alone")
    expectEqual(c.setEnabled(false, access: .granted, now: 11), [])
    expectEqual(c.setEnabled(true, access: .granted, now: 12), [.open(1)], "toggling the feature retries")

    // A reply starts a fresh budget for the next request.
    var d = controller(upTo: .opened, now: 0)
    _ = d.tick(access: .granted, now: 2)                       // attempt 2 of the first request
    _ = feed(&d, reply(0, [reprogIndex, 0, 4]), now: 2.5)      // answered; 0x1D4B lookup sent
    expectEqual(d.tick(access: .granted, now: 4.0), [], "1.5 s after the new request is not yet a timeout")
    expectEqual(d.tick(access: .granted, now: 4.1),
                [.log(.info, "resending HID++ request to MX Master 3S B (attempt 2)"), write(1, getWds)],
                "the new request starts at attempt 1")

    // Giving up while the divert request is in flight also undoes a possible half-applied divert.
    var e = controller(upTo: .wdsKnown, now: 0)
    _ = e.tick(access: .granted, now: 2)
    _ = e.tick(access: .granted, now: 4)
    let gaveUp = e.tick(access: .granted, now: 6)
    expectEqual(nonLog(gaveUp), [write(1, undivertBytes), .close(1)], "undivert write before the close")
    expect(gaveUp.contains(.log(.info, "undiverting CID 0x00C3 on MX Master 3S B")), "the undivert is logged")
    expect(gaveUp.contains(.log(.error, "no HID++ reply from MX Master 3S B after 3 attempts; giving up until reconnect or re-enable")),
           "the give-up is logged")

    // Nothing to do for a healthy session.
    var f = controller(upTo: .diverted)
    expectEqual(f.tick(access: .granted, now: 100), [])
}

// MARK: Writes

private func thumbWriteResultTests() {
    var c = ThumbController()
    _ = c.setEnabled(true, access: .granted, now: 0)
    _ = c.deviceMatched(1, mouse, access: .granted, now: 0)
    _ = c.openFinished(1, code: 0, now: 0)

    // The first payload working keeps the order; the second one working flips it for all later writes.
    expectEqual(c.writeFinished(1, succeededIndex: 0, lastCode: 0), [], "first payload worked")
    expectEqual(nonLog(feed(&c, reply(0, [reprogIndex, 0, 4]))), [write(1, getWds)], "order unchanged")
    expectEqual(c.writeFinished(1, succeededIndex: 1, lastCode: 0), [], "second payload worked")
    expectEqual(nonLog(feed(&c, reply(0, [wdsIndex, 0, 1]))), [write(1, divertBytes, withID: false)], "without-ID first now")
    expectEqual(c.writeFinished(1, succeededIndex: 1, lastCode: 0), [], "the second payload is now the with-ID one")
    expectEqual(feed(&c, divertEcho).count, 1)
    expectEqual(feed(&c, notification(wdsIndex, [0, 1])).last, write(1, divertBytes), "flipped back to with-ID first")

    // A write that failed everywhere is logged and changes nothing else.
    expectEqual(c.writeFinished(1, succeededIndex: nil, lastCode: 0xE00002CD),
                [.log(.error, "SetReport to MX Master 3S B failed (0xE00002CD)")])
    expectEqual(feed(&c, divertEcho).count, 1, "the session carries on")

    // The learned order survives a close/reopen, and the undivert write uses it.
    var d = controller(upTo: .diverted)
    _ = d.writeFinished(1, succeededIndex: 1, lastCode: 0)
    let disabled = d.setEnabled(false, access: .granted, now: 1)
    expectEqual(nonLog(disabled), [write(1, undivertBytes, withID: false), .close(1)], "undivert uses the learned order")
    _ = d.setEnabled(true, access: .granted, now: 2)
    expectEqual(nonLog(d.openFinished(1, code: 0, now: 2)), [write(1, getReprog, withID: false)], "order remembered after reopen")

    // Results for a session that is already gone (the undivert write of a closed or shut-down session).
    var e = controller(upTo: .diverted)
    _ = e.shutdown()
    expectEqual(e.writeFinished(1, succeededIndex: nil, lastCode: 0xE00002CD),
                [.log(.error, "SetReport to device failed (0xE00002CD)")], "failure still logged without a session")
    expectEqual(e.writeFinished(1, succeededIndex: 1, lastCode: 0), [], "success for an unknown session is harmless")
}

// MARK: Disable, removal, shutdown

private func thumbDisableTests() {
    var c = controller(upTo: .diverted)
    expectEqual(c.setEnabled(true, access: .granted, now: 1), [], "already enabled")
    expectEqual(c.setEnabled(false, access: .granted, now: 2),
                [.log(.info, "undiverting CID 0x00C3 on MX Master 3S B"), write(1, undivertBytes), .close(1)],
                "disable undiverts, then closes")
    expect(!c.enabled, "disabled")
    expectEqual(c.setEnabled(false, access: .granted, now: 3), [], "already disabled")
    expectEqual(c.tick(access: .granted, now: 10), [], "a disabled controller stays closed")
    expectEqual(c.setEnabled(true, access: .granted, now: 4), [.open(1)], "enable opens again")

    // Before the feature index is known there is nothing to undo.
    var a = controller(upTo: .opened)
    expectEqual(a.setEnabled(false, access: .granted, now: 1), [.close(1)], "close only")

    // Once the index is known the undivert is sent even if the divert was not yet requested (harmless, safe).
    var b = controller(upTo: .reprogKnown)
    expectEqual(nonLog(b.setEnabled(false, access: .granted, now: 1)), [write(1, undivertBytes), .close(1)])

    // A session that never opened has nothing to close.
    var d = ThumbController()
    _ = d.deviceMatched(1, mouse, access: .granted, now: 0)
    _ = d.setEnabled(true, access: .denied, now: 0)
    expectEqual(d.setEnabled(false, access: .denied, now: 1), [], "never opened")
}

private func thumbRemovalTests() {
    // BLE disconnect: the session is dropped without any I/O.
    var c = controller(upTo: .diverted)
    expectEqual(c.deviceRemoved(1), [.log(.info, "removed MX Master 3S B; dropping session"), .close(1)], "no write on removal")
    expectEqual(feed(&c, thumbDown), [], "reports for a removed device are ignored")
    expectEqual(c.deviceRemoved(1), [], "removing twice is harmless")
    expectEqual(c.deviceRemoved(42), [], "unknown device")

    // Reconnect: matched again → opened and diverted again (the diversion is volatile).
    expectEqual(nonLog(c.deviceMatched(1, mouse, access: .granted, now: 5)), [.open(1)], "match after reconnect opens")
    _ = c.openFinished(1, code: 0, now: 5)
    _ = feed(&c, reply(0, [reprogIndex, 0, 4]), now: 5)
    _ = feed(&c, reply(0, [wdsIndex, 0, 1]), now: 5)
    expectEqual(feed(&c, divertEcho), [.log(.info, "diverted CID 0x00C3 on MX Master 3S B (0x1B04 @ index 9)")], "diverted again")
    expectEqual(feed(&c, thumbDown), [.press], "and the button works")

    // A device that was never opened just disappears.
    var d = ThumbController()
    _ = d.deviceMatched(1, mouse, access: .granted, now: 0)
    expectEqual(d.deviceRemoved(1), [.log(.info, "removed MX Master 3S B; dropping session")], "nothing to close")
}

private func thumbShutdownTests() {
    var c = controller(upTo: .diverted, id: 1)
    _ = c.deviceMatched(2, mouse, access: .granted, now: 0)
    _ = c.openFinished(2, code: 0, now: 0)
    _ = feed(&c, 2, reply(0, [reprogIndex, 0, 4]))
    _ = feed(&c, 2, reply(0, [wdsIndex, 0, 1]))
    _ = feed(&c, 2, divertEcho)

    expectEqual(c.shutdown(),
                [.log(.info, "undiverting CID 0x00C3 on MX Master 3S B"), write(1, undivertBytes), .close(1),
                 .log(.info, "undiverting CID 0x00C3 on MX Master 3S B"), write(2, undivertBytes), .close(2)],
                "every open session is undiverted and closed")
    expect(!c.enabled, "shutdown disables")
    expectEqual(c.shutdown(), [], "safe to call twice")
    expectEqual(feed(&c, 1, thumbDown), [], "sessions are forgotten")
    expectEqual(nonLog(c.deviceMatched(3, mouse, access: .granted, now: 1)), [], "nothing opens after shutdown")
    var empty = ThumbController()
    expectEqual(empty.shutdown(), [], "shutdown without any session")
}

private func thumbMultiDeviceTests() {
    // Each mouse has its own state: held buttons, indices and request budgets do not mix.
    var c = controller(upTo: .diverted, id: 1)
    _ = c.deviceMatched(2, mouse, access: .granted, now: 0)
    _ = c.openFinished(2, code: 0, now: 0)
    _ = feed(&c, 2, reply(0, [reprogIndex, 0, 4]))
    _ = feed(&c, 2, reply(0, [wdsIndex, 0, 1]))
    _ = feed(&c, 2, divertEcho)

    expectEqual(feed(&c, 1, thumbDown), [.press], "mouse 1 pressed")
    expectEqual(feed(&c, 2, thumbDown), [.press], "mouse 2 pressed while mouse 1 is held")
    expectEqual(feed(&c, 1, thumbDown), [], "mouse 1 still held")

    // Only the mouse that was removed is closed.
    expectEqual(c.deviceRemoved(1), [.log(.info, "removed MX Master 3S B; dropping session"), .close(1)])
    expectEqual(feed(&c, 2, thumbUp), [], "mouse 2 carries on")
    expectEqual(feed(&c, 2, thumbDown), [.press])
}

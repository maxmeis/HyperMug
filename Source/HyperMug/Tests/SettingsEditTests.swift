import Foundation
@testable import HyperMugCore

func settingsEditTests() {
    let blank = Data(" \n".utf8)
    let blankEdit = try! SettingsEdit(blank)
    expectEqual(try! SettingsEdit(blankEdit.save(blankEdit.config, current: blank)).config, AppConfig())
    let helperSource = Data(#"{"future":17,"helpers":{"old":"echo old"},"mouse":{"buttons":{"back":{"helper":"old","future":5}}}}"#.utf8)
    let helperEdit = try! SettingsEdit(helperSource)
    var helperDraft = helperEdit.config
    helperDraft.helpers["old"] = "echo new"
    let helperSaved = try! helperEdit.save(helperDraft, current: helperSource)
    let helperRoot = try! JSONSerialization.jsonObject(with: helperSaved) as! [String: Any]
    expectEqual(helperRoot["future"] as? Int, 17)
    expectEqual(((helperRoot["mouse"] as! [String: Any])["buttons"] as! [String: Any])["back"] as? [String: Any] != nil, true)
    expectEqual(try! SettingsEdit(helperSaved).config.mouse.buttons.back, .helper("old"))
    expect((try? helperEdit.save(helperDraft, current: Data("{}".utf8))) == nil)
    helperDraft.helpers.removeValue(forKey: "old")
    expect((try? helperEdit.save(helperDraft, current: helperSource)) == nil)
    helperDraft.mouse.buttons.back = nil
    expect((try? helperEdit.save(helperDraft, current: helperSource)) != nil)
    switch settingsAction(kind: "helper", text: "old") {
    case .success(.helper("old")): break
    default: expect(false)
    }
    if case .success = settingsAction(kind: "helper", text: " ") { expect(false) }
    let source = Data(#"{"future":{"enabled":true},"mouse":{"buttons":{"back":{"shortcut":["cmd","["],"future":7},"future":1},"future":2},"trackpad":{"threeFingerSwipe":{"up":{"shell":"echo hi","future":3}},"future":4}}"#.utf8)
    let edit = try! SettingsEdit(source)
    var draft = edit.config
    draft.capsLock = .hyper
    draft.mouse.invertScroll.vertical = true
    draft.mouse.invertScroll.horizontal = true
    draft.mouse.buttons.back = .shell("echo changed")
    draft.mouse.buttons.forward = .shell("echo forward")
    draft.mouse.buttons.thumb = .shell("echo thumb")
    draft.trackpad.threeFingerSwipe.up = nil
    draft.trackpad.threeFingerSwipe.down = .shell("echo down")
    draft.trackpad.threeFingerSwipe.left = .shell("echo left")
    draft.trackpad.threeFingerSwipe.right = .shell("echo right")
    draft.trackpad.fourFingerSwipe.up = .shell("echo up")
    draft.trackpad.fourFingerSwipe.down = .shell("echo down")
    draft.trackpad.fourFingerSwipe.left = .shell("echo left")
    draft.trackpad.fourFingerSwipe.right = .shell("echo right")
    let saved = try! edit.save(draft, current: source)
    let root = try! JSONSerialization.jsonObject(with: saved) as! [String: Any]
    expect((root["future"] as? [String: Bool])?["enabled"] == true)
    let mouse = root["mouse"] as! [String: Any]
    expectEqual(mouse["future"] as? Int, 2)
    let buttons = mouse["buttons"] as! [String: Any]
    expectEqual(buttons["future"] as? Int, 1)
    expectEqual((buttons["back"] as? [String: Any])?["future"] as? Int, 7)
    let trackpad = root["trackpad"] as! [String: Any]
    expectEqual(trackpad["future"] as? Int, 4)
    let three = trackpad["threeFingerSwipe"] as! [String: Any]
    expectEqual((three["up"] as? [String: Any])?["future"] as? Int, 3)
    expectEqual(try! SettingsEdit(saved).config, draft)
    expect((try? edit.save(draft, current: Data("{}".utf8))) == nil)
    expect((try? SettingsEdit(Data("{".utf8))) == nil)
    expect((try? SettingsEdit(Data("[]".utf8))) == nil)
    switch settingsAction(kind: "shortcut", text: "cmd + [") {
    case .success(.shortcut(let shortcut)): expectEqual(shortcut.tokens, ["cmd", "["])
    default: expect(false)
    }
    switch settingsAction(kind: "shortcut", text: "cmd") {
    case .failure: break
    default: expect(false)
    }
    switch settingsAction(kind: "shell", text: "  ") {
    case .failure: break
    default: expect(false)
    }
    switch settingsAction(kind: "shell", text: "echo yes") {
    case .success(.shell(let command)): expectEqual(command, "echo yes")
    default: expect(false)
    }
    switch settingsAction(kind: "none", text: "") {
    case .success(nil): break
    default: expect(false)
    }
    switch settingsAction(kind: "bad", text: "") {
    case .failure: break
    default: expect(false)
    }
    var second = edit.config
    second.mouse.buttons.back = nil
    let removed = try! edit.save(second, current: source)
    let removedRoot = try! JSONSerialization.jsonObject(with: removed) as! [String: Any]
    let removedBack = (((removedRoot["mouse"] as! [String: Any])["buttons"] as! [String: Any])["back"] as! [String: Any])
    expectEqual(removedBack["future"] as? Int, 7)
}

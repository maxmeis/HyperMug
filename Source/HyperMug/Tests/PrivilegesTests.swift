import Foundation
@testable import HyperMugCore

func privilegesTests() {
    alertModels()
    actionLookup()
    relaunch()
    panes()
}

private func alertModels() {
    let both = privilegesAlert(accessibility: true, inputMonitoring: true)
    expectEqual(both.title, "HyperMug privileges")
    expect(!both.warning, "nothing missing: informational")
    expectEqual(both.buttons.map(\.title), ["Restart HyperMug", "OK"])
    expectEqual(both.buttons.map(\.action), [.restart, .none])
    let lines = both.body.components(separatedBy: "\n")
    expectEqual(lines.count, 4)
    expect(lines[0].hasPrefix("✅ Accessibility — "), lines[0])
    expect(lines[1].hasPrefix("✅ Input Monitoring — "), lines[1])
    expectEqual(lines[2], "")
    expectEqual(lines[3], "After granting Input Monitoring, relaunch HyperMug.")

    let noAX = privilegesAlert(accessibility: false, inputMonitoring: true)
    expect(noAX.warning)
    expect(noAX.body.hasPrefix("❌ Accessibility — "), noAX.body)
    expect(noAX.body.contains("\n✅ Input Monitoring — "), noAX.body)
    expectEqual(noAX.buttons.map(\.title), ["Open Accessibility Settings", "Restart HyperMug", "OK"])
    expectEqual(noAX.buttons.map(\.action), [.requestAccessibility, .restart, .none])

    let noIM = privilegesAlert(accessibility: true, inputMonitoring: false)
    expect(noIM.warning)
    expect(noIM.body.hasPrefix("✅ Accessibility — "), noIM.body)
    expect(noIM.body.contains("\n❌ Input Monitoring — "), noIM.body)
    expectEqual(noIM.buttons.map(\.title), ["Open Input Monitoring Settings", "Restart HyperMug", "OK"])
    expectEqual(noIM.buttons.map(\.action), [.requestInputMonitoring, .restart, .none])

    let neither = privilegesAlert(accessibility: false, inputMonitoring: false)
    expect(neither.warning)
    expect(!neither.body.contains("✅"), neither.body)
    expectEqual(neither.buttons.map(\.title),
                ["Open Accessibility Settings", "Open Input Monitoring Settings", "Restart HyperMug", "OK"])
    expectEqual(neither.buttons.map(\.action), [.requestAccessibility, .requestInputMonitoring, .restart, .none])
}

private func actionLookup() {
    let neither = privilegesAlert(accessibility: false, inputMonitoring: false)
    expectEqual(privilegeAction(responseIndex: 0, in: neither), .requestAccessibility)
    expectEqual(privilegeAction(responseIndex: 1, in: neither), .requestInputMonitoring)
    expectEqual(privilegeAction(responseIndex: 2, in: neither), .restart)
    expectEqual(privilegeAction(responseIndex: 3, in: neither), .none, "OK does nothing")
    expectEqual(privilegeAction(responseIndex: 4, in: neither), .none, "past the last button")
    expectEqual(privilegeAction(responseIndex: -1, in: neither), .none, "before the first button")

    // Indices follow the displayed buttons, so the same index means different things per model.
    let both = privilegesAlert(accessibility: true, inputMonitoring: true)
    expectEqual(privilegeAction(responseIndex: 0, in: both), .restart)
    expectEqual(privilegeAction(responseIndex: 1, in: both), .none)
    expectEqual(privilegeAction(responseIndex: 2, in: both), .none)
}

private func relaunch() {
    let path = "/Applications/My \"Hyper\" $(Mug).app"
    let command = relaunchCommand(bundlePath: path)
    expectEqual(command.path, "/bin/sh")
    expectEqual(command.arguments.count, 3)
    expectEqual(command.arguments[0], "-c")
    expectEqual(command.arguments[1], "sleep 1; /usr/bin/open \"$0\"", "bundle is read from $0")
    expectEqual(command.arguments[2], path, "bundle path is passed as data, never spliced into the script")
    expect(!command.arguments[1].contains(path))
}

private func panes() {
    let ax = URL(string: accessibilityPaneURL)
    let im = URL(string: inputMonitoringPaneURL)
    expect(ax != nil && im != nil, "both pane links parse")
    expectEqual(ax?.scheme, "x-apple.systempreferences")
    expectEqual(im?.scheme, "x-apple.systempreferences")
    expect(ax?.query == "Privacy_Accessibility", "\(String(describing: ax?.query))")
    expect(im?.query == "Privacy_ListenEvent", "\(String(describing: im?.query))")
}

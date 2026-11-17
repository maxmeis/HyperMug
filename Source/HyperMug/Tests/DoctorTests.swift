import Foundation
@testable import HyperMugCore

func doctorTests() {
    let granted = doctorPermissionChecks(accessibility: true, inputMonitoring: true)
    expect(granted.allSatisfy { $0.state == .passed && $0.action == .none })
    let denied = doctorPermissionChecks(accessibility: false, inputMonitoring: false)
    expectEqual(denied.map(\.state), [.blocked, .blocked])
    expectEqual(denied.map(\.action), [.accessibility, .inputMonitoring])
    expect(denied[1].detail.contains("restart"))

    let checks = doctorConflictChecks(preferences: [
        DoctorPreference(name: "Horizontal swipes", value: 2),
        DoctorPreference(name: "Dragging", value: 0, action: .pointer),
        DoctorPreference(name: "Unknown setting", value: nil)],
        runningApps: ["Hyperkey", "BetterTouchTool", "Finder"], secureInputHolder: "Terminal")
    expectEqual(checks.map(\.state), [.warning, .warning, .passed, .unknown, .warning, .warning])
    expect(checks[0].detail.contains("Terminal"))
    expectEqual(checks[2].action, .pointer)
    expectEqual(checks[3].action, .trackpad)
    expect(!checks.contains { $0.title == "Finder" })
    let clear = doctorConflictChecks(preferences: [], runningApps: [], secureInputHolder: nil)
    expectEqual(clear.count, 1)
    expectEqual(clear[0].state, .passed)

    func capture(_ mapped: Bool, _ enabled: Bool, _ devices: Int, _ error: String? = nil) -> DoctorCheck {
        doctorCaptureCheck(hasMappings: mapped, enabled: enabled, devices: devices, error: error)
    }
    expectEqual(capture(false, false, 0).state, .inactive)
    expectEqual(capture(false, false, 0).action, .config)
    expectEqual(capture(true, false, 0).state, .blocked)
    expectEqual(capture(true, true, 0).state, .warning)
    expectEqual(capture(true, true, 1).state, .passed)
    expectEqual(capture(true, true, 1, "Failed to start").detail, "Failed to start")
    expectEqual(capture(true, true, 1, "Failed to start").state, .blocked)
    expectEqual(doctorConfigCheck(error: nil).state, .passed)
    let ignored = doctorConfigCheck(error: nil, unknownKeys: ["mouse.button"])
    expectEqual(ignored.state, .warning)
    expect(ignored.detail.contains("mouse.button"))
    let migrated = doctorConfigCheck(error: nil, notice: .migrated(from: "a.json", to: "a.toml", backup: "a.json.migrated-backup"))
    expectEqual(migrated.state, .passed)
    expect(migrated.detail.contains("Migrated a.json to a.toml"))
    expectEqual(doctorConfigCheck(error: nil, notice: .legacyIgnored(legacy: "a.json", active: "a.toml")).state, .warning)
    let blockedMigration = doctorConfigCheck(error: "bad", notice: .migrationBlocked(from: "a.json", to: "a.toml"))
    expectEqual(blockedMigration.state, .blocked)
    expect(blockedMigration.detail.hasPrefix("bad a.json was not migrated"))
    let invalid = doctorConfigCheck(error: "Invalid JSON")
    expectEqual(invalid.state, .blocked)
    expect(invalid.detail.contains("last valid settings"))
    expectEqual(invalid.action, .config)

    expectEqual(doctorActionLabel(.helper("next")), "Helper: next")
    expectEqual(doctorActionLabel(nil), "Not assigned")
    expectEqual(doctorActionLabel(.shortcut(try! parseShortcut(["cmd", "a"]).get())), "Keyboard shortcut")
    expectEqual(doctorActionLabel(.shell("/opt/homebrew/bin/aerospace workspace --no-stdin next")), "Next AeroSpace workspace")
    expectEqual(doctorActionLabel(.shell("/opt/homebrew/bin/aerospace workspace --no-stdin prev")), "Previous AeroSpace workspace")
    expectEqual(doctorActionLabel(.shell("/opt/homebrew/bin/aerospace workspace A")), "Shell command")
    expectEqual(doctorActionLabel(.shell("open -a Finder")), "Shell command")

    let good = DoctorCheck("Good", "", .passed)
    let warning = DoctorCheck("Warning", "", .warning)
    let blocked = DoctorCheck("Blocked", "", .blocked)
    let unknown = DoctorCheck("Unknown", "", .unknown)
    expectEqual(doctorSummary([good]).state, .passed)
    expectEqual(doctorSummary([]).state, .passed)
    expectEqual(doctorSummary([good, unknown]).state, .unknown)
    expectEqual(doctorSummary([unknown, warning]).state, .warning)
    expectEqual(doctorSummary([warning, blocked, unknown]).state, .blocked)
}

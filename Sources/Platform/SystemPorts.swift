import Foundation
import CoreGraphics
import IOKit.pwr_mgt
import ServiceManagement
import HyperMugCore

/// The real OS behind `Engine`: forwards to the Platform hosts and wraps IOPM / SMAppService.
final class SystemPorts: EnginePorts {
    private let sink: LogSink
    private let tap: EventTapHost
    private let caps: CapsKeyMonitor
    private let thumb: ThumbHID
    private var caffeineAssertion: IOPMAssertionID = 0

    init(log: @escaping LogSink, tap: EventTapHost, caps: CapsKeyMonitor, thumb: ThumbHID) {
        self.sink = log
        self.tap = tap
        self.caps = caps
        self.thumb = thumb
    }

    // MARK: Permissions (module-qualified: the free functions have the same names as the protocol methods)

    func accessibilityTrusted() -> Bool { HyperMug.accessibilityTrusted() }
    func promptAccessibility() { HyperMug.promptAccessibility() }
    func inputMonitoringAccess() -> HIDAccess { HyperMug.inputMonitoringAccess() }

    // MARK: Event tap, Caps monitor, thumb

    func installTap(mask: CGEventMask) -> Bool { tap.install(mask: mask) }
    func removeTap() { tap.remove() }
    func setCapsKeyboardMonitoring(_ on: Bool) { caps.setEnabled(on) }
    func setThumbDiversion(_ on: Bool) { thumb.setEnabled(on) }
    func shutdownThumb() { thumb.shutdown() }

    // MARK: Actions and logs

    func run(_ action: ButtonAction) { ActionRunner.run(action) }
    func postEscape() { ActionRunner.postEscape() }
    func log(_ level: LogLevel, _ message: String) { sink(level, message) }
    func debugLog(_ line: String) { DebugLog.write(line) }

    // MARK: Caffeine

    func acquireCaffeine() -> Bool {
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            AppIdentity.caffeineAssertionName as CFString,
            &id
        )
        guard result == kIOReturnSuccess else { return false }
        caffeineAssertion = id
        return true
    }

    func releaseCaffeine() {
        IOPMAssertionRelease(caffeineAssertion)
        caffeineAssertion = 0
    }

    // MARK: Login item

    func loginItemStatus() -> LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .notRegistered: return .notRegistered
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        @unknown default: return .notFound
        }
    }

    func setLoginItem(registered: Bool) -> String? {
        do {
            if registered {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

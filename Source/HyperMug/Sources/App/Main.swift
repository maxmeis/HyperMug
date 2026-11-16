import AppKit
import HyperMugCore

/// Composition root: builds every Platform adapter, the Core store/engine, wires their callbacks and
/// starts them. It contains no decisions of its own.
private final class HyperMugRuntime {
    let store: ConfigStore
    let tap: EventTapHost
    let caps: CapsKeyMonitor
    let thumb: ThumbHID
    let trackpad: TrackpadCapture
    let ports: SystemPorts
    let engine: Engine
    let updateChecker: UpdateChecker
    let statusItem: StatusItemController
    let configErrorAlert: ConfigErrorAlert
    private var syncTimer: Timer?

    init() {
        DebugLog.reset()   // before anything that writes a debug line
        LegacyCapsRemap.removeIfPresent(log: makeLogSink(category: "legacy-caps"))

        let configURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config")
            .appendingPathComponent(AppIdentity.configFileName)
        store = ConfigStore(url: configURL,
                            environment: makeConfigStoreEnvironment(log: makeLogSink(category: "config")))
        tap = EventTapHost(log: makeLogSink(category: "tap"))
        caps = CapsKeyMonitor(log: makeLogSink(category: "caps"))
        thumb = ThumbHID(log: makeLogSink(category: "thumb"))
        trackpad = TrackpadCapture(log: makeLogSink(category: "trackpad"))
        ports = SystemPorts(log: makeLogSink(category: "engine"), tap: tap, caps: caps, thumb: thumb, trackpad: trackpad)
        engine = Engine(ports: ports)
        updateChecker = UpdateChecker()
        statusItem = StatusItemController(store: store, engine: engine, updateChecker: updateChecker, trackpad: trackpad)
        configErrorAlert = ConfigErrorAlert(store: store)

        tap.handler = { [engine] in engine.handleTapEvent($0) }
        caps.onCapsChange = { [engine] down, nowNanos in engine.capsKeyChanged(down: down, nowNanos: nowNanos) }
        caps.onKeyboardRemoved = { [engine] in engine.capsKeyboardRemoved() }
        thumb.onPress = { [engine] in engine.thumbPressed() }
        ports.onTrackpadSwipe = { [engine] swipe in engine.trackpadSwiped(swipe) }
        engine.onStateChange = { [statusItem] in statusItem.refresh() }
        store.onChange = { [engine, updateChecker] config in
            engine.apply(config)
            updateChecker.apply(autoUpdate: config.autoUpdate)
        }
        store.onError = { [configErrorAlert] error in configErrorAlert.present(error) }
    }

    func start() {
        engine.start()
        thumb.start()
        store.start()   // first onChange performs the first apply

        // Common modes: the timer also fires while a menu or an alert is open.
        let timer = Timer(timeInterval: 2, repeats: true) { [engine, store, thumb] _ in
            engine.sync()
            store.pollFallback()
            thumb.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        syncTimer = timer
    }

    func shutdown() {
        syncTimer?.invalidate()
        syncTimer = nil
        engine.shutdown()
    }

    func showDoctor() { statusItem.showDoctor() }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var runtime: HyperMugRuntime?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let runtime = HyperMugRuntime()
        self.runtime = runtime
        runtime.start()
        if CommandLine.arguments.contains("--doctor") { runtime.showDoctor() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        runtime?.shutdown()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        runtime?.showDoctor()
        return true
    }
}

@main
enum HyperMugMain {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate   // NSApplication holds its delegate weakly
        withExtendedLifetime(delegate) { app.run() }
    }
}

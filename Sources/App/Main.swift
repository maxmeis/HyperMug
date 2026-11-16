import AppKit
import HyperMugCore

/// Composition root: builds every Platform adapter, the Core store/engine, wires their callbacks and
/// starts them. It contains no decisions of its own.
private final class HyperMugRuntime {
    let store: ConfigStore
    let tap: EventTapHost
    let caps: CapsKeyMonitor
    let thumb: ThumbHID
    let engine: Engine
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
        engine = Engine(ports: SystemPorts(log: makeLogSink(category: "engine"), tap: tap, caps: caps, thumb: thumb))
        statusItem = StatusItemController(store: store, engine: engine)
        configErrorAlert = ConfigErrorAlert(store: store)

        tap.handler = { [engine] in engine.handleTapEvent($0) }
        caps.onCapsChange = { [engine] down, nowNanos in engine.capsKeyChanged(down: down, nowNanos: nowNanos) }
        caps.onKeyboardRemoved = { [engine] in engine.capsKeyboardRemoved() }
        thumb.onPress = { [engine] in engine.thumbPressed() }
        engine.onStateChange = { [statusItem] in statusItem.refresh() }
        store.onChange = { [engine] config in engine.apply(config) }
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
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var runtime: HyperMugRuntime?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let runtime = HyperMugRuntime()
        self.runtime = runtime
        runtime.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        runtime?.shutdown()
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

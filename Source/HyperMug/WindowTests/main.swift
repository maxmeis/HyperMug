import AppKit
import HyperMugCore
import ScreenCaptureKit

@MainActor
final class CheckTarget: NSObject {
    let controller: HyperMugWindowController
    init(_ controller: HyperMugWindowController) { self.controller = controller }
    @objc func configuration() { controller.show(configuration: true) }
    @objc func doctor() { controller.show(configuration: false) }
    @objc func save() { controller.saveConfiguration() }
}

@main
struct WindowChecks {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hypermug-window-check-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("hypermug-dev.toml")
        let env = ConfigStoreEnvironment(schemaURL: Bundle.main.url(forResource: AppIdentity.schemaFileName, withExtension: nil), log: { _,_ in }, schedule: { _,_ in Token() }, watch: { _,_ in nil })
        let store = ConfigStore(url: url, environment: env)
        store.start()
        let controller = HyperMugWindowController(store: store, capture: TrackpadCapture(log: { _,_ in }))
        let target = CheckTarget(controller)
        ApplicationMenu.install(settingsTarget: target, settingsAction: #selector(CheckTarget.configuration), doctorAction: #selector(CheckTarget.doctor), saveAction: #selector(CheckTarget.save))
        controller.show(configuration: true)
        Task { @MainActor in
            var failures = 0
            var checks = 0
            func check(_ value: Bool, _ detail: String) {
                checks += 1
                if !value { failures += 1; print("FAIL: \(detail)") }
            }
            @MainActor func textViews(_ view: NSView) -> [NSTextView] {
                (view as? NSTextView).map { [$0] } ?? view.subviews.flatMap(textViews)
            }
            try? await Task.sleep(for: .seconds(1.5))
            let window = app.windows.first { $0.identifier?.rawValue == "hypermug.workspace" }!
            check(window.contentView!.subviews.allSatisfy { $0.frame.height <= window.contentView!.bounds.height + 2 }, "native split content fits the window viewport")
            check(window.isVisible, "shared native window is visible")
            check(window.contentView!.bounds.height <= 700, "a long configuration stays in a bounded scrolling editor")
            var editor = textViews(window.contentView!).first { $0.isEditable }!
            window.setContentSize(NSSize(width: 780, height: 540))
            try? await Task.sleep(for: .milliseconds(150))
            check(window.contentView!.bounds.width <= 800 && window.contentView!.bounds.height <= 600, "native window supports its minimum size")
            window.setContentSize(NSSize(width: 880, height: 650))
            check(editor.string.contains("shellTimeoutSeconds") && editor.string.contains("helpers"), "real TOML editor is loaded")
            check(!editor.isRichText && !editor.isAutomaticQuoteSubstitutionEnabled && editor.allowsUndo, "plain native text editing")
            if let capturePath = ProcessInfo.processInfo.environment["HYPERMUG_TEST_CAPTURE_DIRECTORY"],
               CGPreflightScreenCaptureAccess(),
               let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true),
               let ownWindow = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) {
                let configuration = SCStreamConfiguration()
                configuration.width = Int(ownWindow.frame.width)
                configuration.height = Int(ownWindow.frame.height)
                if let image = try? await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: ownWindow), configuration: configuration),
                   let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
                    let destination = URL(fileURLWithPath: capturePath, isDirectory: true)
                    try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                    try? png.write(to: destination.appendingPathComponent("configuration.png"))
                    print("Own-window compositor capture saved using existing permission")
                }
            } else { print("No screen capture permission requested; compositor capture skipped") }
            let initial = try! Data(contentsOf: url)
            window.makeFirstResponder(editor)
            editor.selectAll(nil)
            editor.insertText("{", replacementRange: editor.selectedRange())
            check(controller.hasUnsavedChanges, "native text changes mark the document edited")
            editor.undoManager?.undo()
            check(!controller.hasUnsavedChanges, "native Undo restores the loaded configuration")
            editor.undoManager?.redo()
            check(controller.hasUnsavedChanges && editor.string == "{", "native Redo restores the draft")
            target.save()
            check(try! Data(contentsOf: url) == initial, "invalid native Save leaves disk unchanged")
            editor.selectAll(nil)
            editor.insertText(#"capsLock = "hyper""#, replacementRange: editor.selectedRange())
            let saveEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "s", charactersIgnoringModifiers: "s", isARepeat: false, keyCode: 1)!
            check(app.mainMenu!.performKeyEquivalent(with: saveEvent), "Command-S is handled by the app menu")
            try? await Task.sleep(for: .milliseconds(150))
            check(store.config.capsLock == .hyper && !controller.hasUnsavedChanges, "Command-S validates, saves and applies")
            target.doctor()
            try? await Task.sleep(for: .milliseconds(200))
            check(app.windows.filter { $0.identifier?.rawValue == "hypermug.workspace" }.count == 1, "Doctor reuses the same window")
            target.configuration()
            try? await Task.sleep(for: .milliseconds(200))
            check(window.isVisible && app.windows.filter { $0.identifier?.rawValue == "hypermug.workspace" }.count == 1, "Settings reuses the same window")
            controller.show()
            try? await Task.sleep(for: .milliseconds(100))
            check(!textViews(window.contentView!).filter { $0.isEditable }.isEmpty, "reopening preserves the selected configuration page")
            editor = textViews(window.contentView!).first { $0.isEditable }!
            window.makeFirstResponder(editor)
            editor.selectAll(nil)
            editor.insertText("# defaults", replacementRange: editor.selectedRange())
            window.performClose(nil)
            try? await Task.sleep(for: .milliseconds(100))
            check(window.attachedSheet != nil && window.isVisible, "closing a dirty configuration asks before discarding")
            if let sheet = window.attachedSheet { window.endSheet(sheet, returnCode: .alertFirstButtonReturn) }
            try? await Task.sleep(for: .milliseconds(200))
            check(controller.hasUnsavedChanges && window.isVisible, "Keep Editing preserves draft and window")
            window.performClose(nil)
            try? await Task.sleep(for: .milliseconds(100))
            if let sheet = window.attachedSheet { window.endSheet(sheet, returnCode: .alertSecondButtonReturn) }
            try? await Task.sleep(for: .milliseconds(900))
            check(!controller.hasUnsavedChanges && !window.isVisible, "explicit discard closes without a write")
            check(store.config.capsLock == .hyper, "discard never applies the unsaved configuration")
            print("Native unified window: \(checks) checks, \(failures) failures; temporary config, capture disabled")
            try? FileManager.default.removeItem(at: directory)
            withExtendedLifetime(target) {}
            exit(failures == 0 ? 0 : 1)
        }
        withExtendedLifetime(target) { app.run() }
    }
    private final class Token: Cancellable { func cancel() {} }
}

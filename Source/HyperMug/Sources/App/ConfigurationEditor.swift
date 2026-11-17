import AppKit
import SwiftUI
import HyperMugCore

@MainActor
final class ConfigurationEditorModel: ObservableObject {
    @Published private(set) var draft = ConfigDocumentDraft()
    @Published private(set) var message: String?
    @Published private(set) var messageIsError = false
    var onChange: (() -> Void)?
    private let store: ConfigStore
    var url: URL { store.url }

    init(store: ConfigStore) { self.store = store }

    func edit(_ text: String) {
        draft.text = text
        message = nil
        messageIsError = false
        onChange?()
    }

    func reload() {
        store.createIfAbsent()
        do {
            try draft.load(store.readDocument())
            showDiskValidation()
            onChange?()
        } catch { failed(error) }
    }

    func refreshFromDisk() {
        guard draft.isLoaded else { return }
        do {
            let previous = draft.text
            try draft.observe(store.readDocument())
            if previous != draft.text { showDiskValidation() }
            onChange?()
        } catch { failed(error) }
    }

    func validate() {
        guard !isBlankConfigData(Data(draft.text.utf8)) else {
            failed(ConfigError(reason: "Configuration cannot be empty. Use {} for default settings."))
            return
        }
        switch validateConfigDocument(Data(draft.text.utf8)) {
        case .success:
            messageIsError = false
            message = "Valid JSON, schema and action references. Save to apply."
        case .failure(let error): failed(error)
        }
    }

    func discardChanges() {
        draft.discardChanges()
        message = nil
        messageIsError = false
        onChange?()
    }

    func save() {
        guard draft.isLoaded && draft.isModified else { return }
        do {
            try store.saveDocument(Data(draft.text.utf8), replacing: draft.savedData)
            try draft.load(store.readDocument())
            messageIsError = false
            message = "Saved. The configuration is active."
            onChange?()
        } catch { failed(error) }
    }

    private func failed(_ error: Error) {
        messageIsError = true
        message = (error as? ConfigError)?.reason ?? error.localizedDescription
    }

    private func showDiskValidation() {
        message = nil
        messageIsError = false
        if case .failure(let error) = validateConfigDocument(Data(draft.text.utf8)) { failed(error) }
    }
}

struct ConfigurationEditorView: View {
    @ObservedObject var model: ConfigurationEditorModel
    @State private var confirmingReload = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Configuration").font(.title2.bold())
                        Text("One JSON file for every binding and preference.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Reveal File", systemImage: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([model.url])
                    }
                    .help("Show the configuration file in Finder")
                }
                Text(model.url.path).font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary).textSelection(.enabled)
                if model.draft.hasExternalChanges {
                    Label("The file changed elsewhere. Your draft is preserved. Copy it if needed, then reload before saving.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
            }.padding(20)
            Divider()
            JSONSourceEditor(text: Binding(get: { model.draft.text }, set: model.edit), editable: model.draft.isLoaded)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Text(model.message ?? "Save applies your file. Invalid drafts keep the last valid settings active.")
                    .font(.callout).foregroundStyle(model.messageIsError ? Color.red : Color.secondary)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text(model.draft.isModified ? "Unsaved changes" : "Saved file")
                        .foregroundStyle(.secondary)
                    Text("· \(model.draft.text.components(separatedBy: "\n").count) lines")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reload") {
                        if model.draft.isModified { confirmingReload = true }
                        else { model.reload() }
                    }
                    Button("Validate", action: model.validate).disabled(!model.draft.isLoaded)
                    Button("Save", action: model.save)
                        .keyboardShortcut("s", modifiers: .command)
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.draft.isLoaded || !model.draft.isModified || model.draft.hasExternalChanges)
                }
            }.padding(20)
        }
        .onAppear { if !model.draft.isLoaded { model.reload() } }
        .alert("Discard unsaved changes?", isPresented: $confirmingReload) {
            Button("Keep Editing", role: .cancel) {}
            Button("Reload File", role: .destructive, action: model.reload)
        } message: { Text("Reload replaces this draft with the current file on disk.") }
    }
}

/// AppKit supplies selection, undo, find, keyboard editing and accessibility for the raw file.
private struct JSONSourceEditor: NSViewRepresentable {
    @Binding var text: String
    let editable: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = JSONScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        let view = NSTextView(frame: scroll.bounds)
        scroll.documentView = view
        view.minSize = .zero
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.isVerticallyResizable = true
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.usesFindBar = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.isGrammarCheckingEnabled = false
        view.isAutomaticDataDetectionEnabled = false
        view.isAutomaticLinkDetectionEnabled = false
        view.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        view.textColor = .textColor
        view.backgroundColor = .textBackgroundColor
        view.textContainerInset = NSSize(width: 16, height: 16)
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: .greatestFiniteMagnitude)
        view.setAccessibilityLabel("JSON configuration editor")
        view.delegate = context.coordinator
        context.coordinator.watchUndo(in: view)
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.text = $text
        let view = scroll.documentView as! NSTextView
        view.isEditable = editable
        guard !view.hasMarkedText(), !context.coordinator.undo.isUndoing, !context.coordinator.undo.isRedoing else { return }
        guard view.string != text else { return }
        let selection = view.selectedRange()
        view.string = text
        view.undoManager?.removeAllActions()
        view.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
    }

    func makeCoordinator() -> Coordinator { Coordinator($text) }

    // The document's length determines scrolling, never the window's minimum height.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        let width = proposal.width.flatMap { $0.isFinite ? max(0, $0) : nil } ?? 600
        let height = proposal.height.flatMap { $0.isFinite ? max(0, $0) : nil } ?? 300
        return CGSize(width: width, height: height)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        let undo = UndoManager()
        private var observers: [NSObjectProtocol] = []
        init(_ text: Binding<String>) { self.text = text }
        deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) } }
        func undoManager(for view: NSTextView) -> UndoManager? { undo }
        func watchUndo(in view: NSTextView) {
            for name in [Notification.Name.NSUndoManagerDidUndoChange, Notification.Name.NSUndoManagerDidRedoChange] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: undo, queue: .main) { [weak self, weak view] _ in
                    MainActor.assumeIsolated {
                        guard let self, let view else { return }
                        self.text.wrappedValue = view.string
                    }
                })
            }
        }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            text.wrappedValue = view.string
        }
    }
}

private final class JSONScrollView: NSScrollView {
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric) }
    override var fittingSize: NSSize { .zero }
}

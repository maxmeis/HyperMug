import AppKit
import HyperMugCore

/// The "Secure Input" details panel: one reusable floating HUD panel, refreshed every 2 s while visible.
/// Everything runs on the main thread; confirmations and errors are sheets, so nothing blocks it.
/// Texts, enabled states and placement come from Core (`secureInputPanelModel`, `panelOrigin`, `terminationPrompt`).
final class SecureInputWindowController: NSObject, NSWindowDelegate {
    /// Current Secure Input state and the time of the first poll that saw it on (owned by the status item).
    typealias Snapshot = () -> (info: SecureInputInfo?, since: Date?)

    private let snapshot: Snapshot
    private var window: NSPanel?
    private var timer: Timer?
    private var current: SecureInputInfo?
    private var model: SecureInputPanelModel?

    private let statusLabel = NSTextField(labelWithString: "")
    private let appValue = SecureInputWindowController.valueLabel()
    private let pidValue = SecureInputWindowController.valueLabel()
    private let bundleValue = SecureInputWindowController.valueLabel()
    private let pathValue = SecureInputWindowController.valueLabel()
    private let ownerValue = SecureInputWindowController.valueLabel()
    private let frontmostValue = SecureInputWindowController.valueLabel()
    private let sinceValue = SecureInputWindowController.valueLabel()
    private let sessionsValue = SecureInputWindowController.valueLabel()
    private let reasonLabel = NSTextField(wrappingLabelWithString: "")
    private let bringButton = NSButton(title: "Bring to Front", target: nil, action: nil)
    private let quitButton = NSButton(title: "Quit", target: nil, action: nil)
    private let forceButton = NSButton(title: "Force Quit", target: nil, action: nil)

    init(snapshot: @escaping Snapshot) {
        self.snapshot = snapshot
        super.init()
    }

    /// Opens (or re-opens) the floating panel, brings it to front and activates the app.
    /// A panel that is already visible keeps the position the user dragged it to.
    func show(anchor: NSView?) {
        let panel = self.window ?? makePanel()
        self.window = panel
        let wasVisible = panel.isVisible
        update()
        startTimer()
        if !wasVisible { position(panel, below: anchor) }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    /// Just below the status item, right-aligned to it, kept inside the screen's visible frame (placement is Core).
    private func position(_ panel: NSPanel, below anchor: NSView?) {
        let anchorWindow = anchor?.window
        let anchorRect = anchor.flatMap { view in
            anchorWindow?.convertToScreen(view.convert(view.bounds, to: nil))
        }
        let visible = (anchorWindow?.screen ?? NSScreen.main)?.visibleFrame
        if let origin = panelOrigin(anchor: anchorRect, panelSize: panel.frame.size, visible: visible) {
            panel.setFrameOrigin(origin)
        } else {
            panel.center()
        }
    }

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Layout

    private static func valueLabel() -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: "")
        label.isSelectable = true
        label.lineBreakMode = .byCharWrapping
        label.preferredMaxLayoutWidth = 380
        return label
    }

    private static func rowLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        return label
    }

    private func makePanel() -> NSPanel {
        // HUD style: the panel gets the dark vibrant appearance itself, so labelColor/secondaryLabelColor stay readable.
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 470),
            styleMask: [.titled, .closable, .utilityWindow, .hudWindow, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.title = "Secure Input"
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.delegate = self

        statusLabel.font = .boldSystemFont(ofSize: 14)

        let rows: [[NSView]] = [
            [Self.rowLabel("Status"), statusLabel],
            [Self.rowLabel("On since"), sinceValue],
            [Self.rowLabel("App"), appValue],
            [Self.rowLabel("PID"), pidValue],
            [Self.rowLabel("Bundle ID"), bundleValue],
            [Self.rowLabel("Path"), pathValue],
            [Self.rowLabel("Owner"), ownerValue],
            [Self.rowLabel("Frontmost"), frontmostValue],
            [Self.rowLabel("Sessions"), sessionsValue],
        ]
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 8
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 0).width = 90
        for index in 0..<rows.count { grid.row(at: index).yPlacement = .top }
        sessionsValue.font = .monospacedSystemFont(ofSize: 11, weight: .regular)

        bringButton.target = self
        bringButton.action = #selector(bringToFront)
        quitButton.target = self
        quitButton.action = #selector(quitHolder)
        forceButton.target = self
        forceButton.action = #selector(forceQuitHolder)
        let buttons = NSStackView(views: [bringButton, quitButton, forceButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        reasonLabel.textColor = .secondaryLabelColor
        reasonLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .labelColor
        for label in [appValue, pidValue, bundleValue, pathValue, ownerValue, frontmostValue, sinceValue, sessionsValue] {
            label.textColor = .labelColor
        }

        let stack = NSStackView(views: [grid, buttons, reasonLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
        ])
        panel.contentView = content
        return panel
    }

    // MARK: - Refresh

    private func startTimer() {
        guard timer == nil else { return }
        // Common modes: keeps refreshing while a confirmation sheet is up.
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            guard let self, self.window?.isVisible == true else { return }
            self.update()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func update() {
        let (info, since) = snapshot()
        current = info
        let model = secureInputPanelModel(
            info: info, sinceText: since.map(Self.format(date:)),
            protection: info.flatMap { protection(for: $0.holder) })
        self.model = model

        statusLabel.stringValue = model.status
        sinceValue.stringValue = model.since
        appValue.stringValue = model.app
        pidValue.stringValue = model.pid
        bundleValue.stringValue = model.bundleID
        pathValue.stringValue = model.path
        ownerValue.stringValue = model.owner
        frontmostValue.stringValue = model.frontmost
        sessionsValue.stringValue = model.sessions
        reasonLabel.stringValue = model.reason
        bringButton.isEnabled = model.bringEnabled
        quitButton.isEnabled = model.quitEnabled
        forceButton.isEnabled = model.forceQuitEnabled
    }

    /// Locale- and calendar-dependent, so it stays here.
    private static func format(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = Calendar.current.isDateInToday(date) ? .none : .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private func protection(for holder: SecureInputHolder) -> String? {
        protectionReason(holder, selfPID: SecureInputReader.selfPID, currentUID: SecureInputReader.currentUID)
    }

    // MARK: - Actions

    @objc private func bringToFront() {
        guard let pid = current?.holder.pid else { return }
        SecureInputReader.activate(pid: pid)
    }

    @objc private func quitHolder() { confirmTermination(force: false) }
    @objc private func forceQuitHolder() { confirmTermination(force: true) }

    private func confirmTermination(force: Bool) {
        guard let holder = current?.holder, model?.quitEnabled == true, let window, window.isVisible else { return }
        let prompt = terminationPrompt(holderName: holder.name, pid: holder.pid, force: force)
        let alert = NSAlert()
        alert.messageText = prompt.title
        alert.informativeText = prompt.body
        alert.alertStyle = .warning
        alert.addButton(withTitle: prompt.confirmButton)
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.terminate(pid: holder.pid, force: force)
        }
    }

    /// Re-checks the protections against fresh process facts, then asks the app to quit (or kills it).
    private func terminate(pid: Int32, force: Bool) {
        let fresh = makeHolder(SecureInputReader.facts(pid: pid))
        if let reason = protection(for: fresh) {
            showError("Not allowed", reason)
        } else if let detail = SecureInputReader.terminate(pid: pid, force: force) {
            showError(terminationFailureTitle(force: force, name: fresh.name, pid: pid), detail)
        } else {
            update()
        }
    }

    private func showError(_ title: String, _ detail: String) {
        guard let window, window.isVisible else { return }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window, completionHandler: nil)
    }
}

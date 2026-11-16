import AppKit
import SwiftUI
import HyperMugCore

private enum DoctorPage: String, CaseIterable, Identifiable {
    case overview = "Overview", permissions = "Permissions", conflicts = "Conflicts", activity = "Activity"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .overview: return "stethoscope"
        case .permissions: return "hand.raised"
        case .conflicts: return "arrow.triangle.branch"
        case .activity: return "waveform.path"
        }
    }
}

private final class DoctorModel: ObservableObject {
    @Published var permissions: [DoctorCheck] = []
    @Published var conflicts: [DoctorCheck] = []
    @Published var overview: [DoctorCheck] = []
    @Published var summary = DoctorCheck("Checking…", "", .unknown)
    @Published var logs = ""
    @Published var config = AppConfig()
    @Published var updated = Date()
    private let store: ConfigStore
    private let capture: TrackpadCapture

    init(store: ConfigStore, capture: TrackpadCapture) {
        self.store = store
        self.capture = capture
    }

    func refresh() {
        config = store.config
        permissions = doctorPermissionChecks(accessibility: accessibilityTrusted(),
            inputMonitoring: inputMonitoringAccess() == .granted)
        conflicts = doctorConflictChecks(preferences: DoctorReader.preferences(),
            runningApps: DoctorReader.runningApps(), secureInputHolder: SecureInputReader.current()?.holder.name)
        overview = [doctorConfigCheck(error: store.error?.reason, unknownKeys: store.unknownKeys),
            doctorCaptureCheck(hasMappings: config.trackpad.hasMappings, enabled: capture.isEnabled,
                devices: capture.deviceCount, error: capture.captureError)]
        summary = doctorSummary(permissions + overview + conflicts)
        logs = DebugLog.recentText()
        updated = Date()
    }

    func perform(_ action: DoctorAction) {
        switch action {
        case .none: break
        case .accessibility: PrivilegeActions.requestAccessibility()
        case .inputMonitoring: PrivilegeActions.requestInputMonitoring()
        case .trackpad:
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension")!)
        case .pointer:
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess?Mouse")!)
        case .config:
            store.createIfAbsent()
            EditorLauncher.open(store.url)
        }
    }

    func copyReport() {
        refresh()
        let checks = permissions + overview + conflicts
        let report = ["HyperMug Doctor", "Checked: \(updated.formatted())", summary.title,
            checks.map { "\($0.title): \($0.state.rawValue)\n\($0.detail)" }.joined(separator: "\n\n"),
            "Recent activity\n\(logs)"].joined(separator: "\n\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
    }
}

final class DoctorWindowController: NSObject, NSWindowDelegate {
    private let model: DoctorModel
    private var window: NSWindow?
    private var timer: Timer?

    init(store: ConfigStore, capture: TrackpadCapture) {
        model = DoctorModel(store: store, capture: capture)
    }

    func show() {
        DebugLog.write("Doctor show requested")
        NSApp.setActivationPolicy(.regular)
        let panel = window ?? makeWindow()
        window = panel
        model.refresh()
        timer?.invalidate()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.model.refresh() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        RunLoop.main.perform(inModes: [.common]) {
            NSApp.activate(ignoringOtherApps: true)
            panel.deminiaturize(nil)
            panel.makeKeyAndOrderFront(nil)
            panel.orderFrontRegardless()
            DebugLog.write("Doctor window visible=\(panel.isVisible) frame=\(panel.frame)")
        }
    }

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
        NSApp.setActivationPolicy(.accessory)
    }

    private func makeWindow() -> NSWindow {
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 650),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        panel.title = "\(AppIdentity.appName) Doctor"
        panel.subtitle = AppIdentity.appName
        panel.titlebarAppearsTransparent = true
        panel.toolbarStyle = .unified
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 780, height: 540)
        panel.setFrameAutosaveName("HyperMugDoctor")
        panel.delegate = self
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.contentViewController = NSHostingController(rootView: DoctorView(model: model))
        panel.setContentSize(NSSize(width: 880, height: 650))
        panel.center()
        return panel
    }
}

private struct DoctorView: View {
    @ObservedObject var model: DoctorModel
    @State private var page: DoctorPage? = .overview
    @State private var search = ""
    @State private var paused = false
    @State private var pausedLogs = ""
    @State private var copied = false

    var body: some View {
        NavigationSplitView {
            List(DoctorPage.allCases, selection: $page) { page in
                Label(page.rawValue, systemImage: page.symbol).tag(page)
                    .padding(.vertical, 4)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 210)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(AppIdentity.appName).font(.headline)
                    Label("Checks update every 2 seconds", systemImage: "arrow.clockwise")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }
        } detail: {
            VStack(spacing: 0) {
                switch page ?? .overview {
                case .overview: overview
                case .permissions: permissions
                case .conflicts: conflicts
                case .activity: activity
                }
                Divider()
                HStack {
                    Text("Checked \(model.updated.formatted(date: .omitted, time: .standard))")
                    Spacer()
                    Button("Check Again", action: model.refresh).buttonStyle(.link)
                }
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.vertical, 10)
            }
            .navigationTitle((page ?? .overview).rawValue)
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        model.copyReport()
                        copied = true
                    } label: {
                        Label(copied ? "Copied" : "Copy Report", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .help("Copy diagnostic checks and recent activity")
                    Button { model.perform(.config) } label: { Label("Open Configuration", systemImage: "doc.text") }
                        .help("Open the HyperMug configuration")
                }
            }
            .onChange(of: page) { _, _ in copied = false }
        }
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top, spacing: 16) {
                    stateIcon(model.summary.state).font(.system(size: 38))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.summary.title).font(.title2.bold())
                        Text(model.summary.detail).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 8)
                GroupBox {
                    VStack(spacing: 0) {
                        ForEach(Array((model.permissions + model.overview).enumerated()), id: \.offset) { index, check in
                            if index > 0 { Divider() }
                            checkRow(check)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Mouse controls").font(.headline)
                    GroupBox {
                        VStack(spacing: 10) {
                            LabeledContent("Back button", value: doctorActionLabel(model.config.mouse.buttons.back))
                            LabeledContent("Forward button", value: doctorActionLabel(model.config.mouse.buttons.forward))
                            LabeledContent("Thumb button", value: doctorActionLabel(model.config.mouse.buttons.thumb))
                            Divider()
                            LabeledContent("Vertical scroll", value: model.config.mouse.invertScroll.vertical ? "Reversed" : "System direction")
                            LabeledContent("Horizontal scroll", value: model.config.mouse.invertScroll.horizontal ? "Reversed" : "System direction")
                        }.font(.callout).padding(8)
                    }
                    Button("Edit Configuration") { model.perform(.config) }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Swipe controls").font(.headline)
                    Text("Lift all fingers between swipes. Activity shows each detected swipe and its command result.")
                        .font(.callout).foregroundStyle(.secondary)
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach([3, 4], id: \.self) { fingers in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("\(fingers)-finger swipes").font(.subheadline.bold())
                                    ForEach(SwipeDirection.allCases, id: \.rawValue) { direction in
                                        HStack {
                                            Text(direction.rawValue.capitalized).frame(width: 48, alignment: .leading)
                                                .foregroundStyle(.secondary)
                                            Text(doctorActionLabel(model.config.trackpad.action(fingers: fingers, direction: direction)))
                                            Spacer()
                                        }.font(.callout)
                                    }
                                }
                                if fingers == 3 { Divider() }
                            }
                        }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Button("Review Possible Conflicts") { page = .conflicts }
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var permissions: some View {
        Form {
            Section {
                ForEach(Array(model.permissions.enumerated()), id: \.offset) { _, check in checkRow(check) }
            } header: { Text("Required permissions") }
            Section {
                Text("macOS controls these permissions. HyperMug cannot grant them automatically.")
                Text("After changing Input Monitoring, restart HyperMug to apply the change.")
                    .foregroundStyle(.secondary)
                Button("Restart \(AppIdentity.appName)", action: PrivilegeActions.relaunch)
            } header: { Text("Apply permission changes") }
        }.formStyle(.grouped)
    }

    private var conflicts: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Check for overlapping controls").font(.title2.bold())
                Text("macOS gestures and other input apps can handle the same action. These checks do not change your settings.")
                    .foregroundStyle(.secondary)
                GroupBox {
                    VStack(spacing: 0) {
                        ForEach(Array(model.conflicts.enumerated()), id: \.offset) { index, check in
                            if index > 0 { Divider() }
                            checkRow(check)
                        }
                    }
                }
                Text("A saved setting does not prove that a gesture is active. Check Mission Control, App Exposé, and full-screen app swipes in Trackpad settings. Check three-finger dragging in Pointer settings.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }
    }

    private var activity: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Test a swipe").font(.title2.bold())
            Text("Look for “swipe recognized”, then “shell action exited status=0”. A nonzero status means that the command failed.")
                .foregroundStyle(.secondary)
            HStack {
                TextField("Filter activity", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Filter activity")
                Toggle("Pause", isOn: $paused).toggleStyle(.button)
                    .onChange(of: paused) { _, value in if value { pausedLogs = model.logs } }
                Menu("Logs") {
                    Button("Open Current Log") { NSWorkspace.shared.open(DebugLog.fileURL) }
                    Button("Show Log Folder") { NSWorkspace.shared.activateFileViewerSelecting([DebugLog.fileURL]) }
                }
            }
            ScrollView([.vertical, .horizontal]) {
                Text(filteredLogs)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(12)
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
            Text("Recent activity updates automatically. Typed keys and command contents are not recorded here.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(24)
    }

    private var filteredLogs: String {
        let lines = (paused ? pausedLogs : model.logs).split(separator: "\n")
            .filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) }
        return lines.isEmpty ? "No matching activity." : lines.joined(separator: "\n")
    }

    private func checkRow(_ check: DoctorCheck) -> some View {
        HStack(alignment: .top, spacing: 12) {
            stateIcon(check.state).font(.title3).frame(width: 24).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(check.title).font(.headline)
                Text(check.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if check.action != .none {
                Button(check.action == .config ? "Open Configuration" : "Open System Settings") { model.perform(check.action) }
                    .controlSize(.small)
            }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func stateIcon(_ state: DoctorState) -> some View {
        switch state {
        case .passed: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .warning: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .blocked: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .unknown: Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
        case .inactive: Image(systemName: "minus.circle").foregroundStyle(.secondary)
        }
    }
}

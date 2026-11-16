import AppKit
import SwiftUI
import HyperMugCore

private struct ActionDraft {
    var kind: String = "none"
    var text: String = ""
    init(_ action: ButtonAction?) {
        switch action {
        case .shortcut(let value): kind = "shortcut"; text = value.tokens.joined(separator: " + ")
        case .shell(let value): kind = "shell"; text = value
        case .helper(let value): kind = "helper"; text = value
        case nil: break
        }
    }
}

private struct HelperDraft: Identifiable {
    let id = UUID()
    var name: String
    var command: String
}

private final class SettingsState: ObservableObject {
    @Published var config = AppConfig()
    @Published var actions: [String: ActionDraft] = [:]
    @Published var helpers: [HelperDraft] = []
    @Published var error: String?
    @Published var selectedTab = 0
    private var edit: SettingsEdit?
    let url: URL

    init(url: URL) { self.url = url; reload() }

    func reload() {
        do {
            let snapshot = try SettingsEdit(Data(contentsOf: url))
            edit = snapshot
            config = snapshot.config
            helpers = config.helpers.keys.sorted().map { HelperDraft(name: $0, command: config.helpers[$0]!) }
            actions = [
                "back": ActionDraft(config.mouse.buttons.back), "forward": ActionDraft(config.mouse.buttons.forward),
                "thumb": ActionDraft(config.mouse.buttons.thumb)
            ]
            for fingers in [3, 4] {
                let map = fingers == 3 ? config.trackpad.threeFingerSwipe : config.trackpad.fourFingerSwipe
                for direction in SwipeDirection.allCases {
                    actions["\(fingers).\(direction.rawValue)"] = ActionDraft(map.action(for: direction))
                }
            }
            error = nil
        } catch {
            edit = nil
            self.error = "Cannot load the config: \(error.localizedDescription)"
        }
    }

    func save() {
        guard let edit else { error = "Repair the config file, then reload Settings."; return }
        var draft = config
        do {
            var names = Set<String>()
            draft.helpers = [:]
            for helper in helpers {
                let name = helper.name
                guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ConfigError(reason: "Helper name cannot be empty")
                }
                guard names.insert(name).inserted else { throw ConfigError(reason: "Duplicate helper name: \(name)") }
                guard !helper.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ConfigError(reason: "Helper \(name): command cannot be empty")
                }
                draft.helpers[name] = helper.command
            }
            func action(_ key: String) throws -> ButtonAction? {
                let entry = actions[key] ?? ActionDraft(nil)
                switch settingsAction(kind: entry.kind, text: entry.text) {
                case .success(let value): return value
                case .failure(let reason): throw ConfigError(reason: "\(key): \(reason.reason)")
                }
            }
            draft.mouse.buttons.back = try action("back")
            draft.mouse.buttons.forward = try action("forward")
            draft.mouse.buttons.thumb = try action("thumb")
            for fingers in [3, 4] {
                var map = fingers == 3 ? draft.trackpad.threeFingerSwipe : draft.trackpad.fourFingerSwipe
                map.up = try action("\(fingers).up")
                map.down = try action("\(fingers).down")
                map.left = try action("\(fingers).left")
                map.right = try action("\(fingers).right")
                if fingers == 3 { draft.trackpad.threeFingerSwipe = map }
                else { draft.trackpad.fourFingerSwipe = map }
            }
            for (key, entry) in actions where entry.kind == "helper" && draft.helpers[entry.text] == nil {
                throw ConfigError(reason: "\(key): helper \"\(entry.text)\" is missing. Choose another helper or restore its name.")
            }
            let data = try edit.save(draft, current: Data(contentsOf: url))
            try data.write(to: url.resolvingSymlinksInPath(), options: .atomic)
            reload()
        } catch let reason as ConfigError {
            error = reason.reason
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct ActionRow: View {
    let title: String
    let key: String
    @ObservedObject var state: SettingsState

    var body: some View {
        HStack {
            Text(title).frame(width: 100, alignment: .leading)
            Picker("Action for \(title)", selection: Binding(
                get: { state.actions[key]?.kind ?? "none" },
                set: { state.actions[key, default: ActionDraft(nil)].kind = $0 }
            )) {
                Text("Unmapped").tag("none")
                Text("Shortcut").tag("shortcut")
                Text("Shell command").tag("shell")
                Text("Helper").tag("helper")
            }.labelsHidden().frame(width: 150)
            if state.actions[key]?.kind == "helper" {
                Picker("Helper for \(title)", selection: Binding(
                    get: { state.actions[key]?.text ?? "" },
                    set: { state.actions[key, default: ActionDraft(nil)].text = $0 }
                )) {
                    Text("Choose helper").tag("")
                    ForEach(state.helpers.map(\.name).sorted(), id: \.self) { name in Text(name).tag(name) }
                }
            } else if state.actions[key]?.kind != "none" {
                TextField(state.actions[key]?.kind == "shell" ? "Command" : "cmd + [", text: Binding(
                    get: { state.actions[key]?.text ?? "" },
                    set: { state.actions[key, default: ActionDraft(nil)].text = $0 }
                ))
                .accessibilityLabel("\(title) \(state.actions[key]?.kind == "shell" ? "shell command" : "shortcut")")
            }
        }
    }
}

private struct SettingsView: View {
    @ObservedObject var state: SettingsState
    var body: some View {
        VStack(spacing: 0) {
            Picker("Settings section", selection: $state.selectedTab) {
                Text("General").tag(0); Text("Mouse").tag(1); Text("Trackpad").tag(2); Text("Helpers").tag(3)
            }.pickerStyle(.segmented).padding()
            Divider()
            ScrollView {
                Form {
                    if state.selectedTab == 0 { general }
                    if state.selectedTab == 1 { mouse }
                    if state.selectedTab == 2 { trackpad }
                    if state.selectedTab == 3 { helpers }
                }.formStyle(.grouped)
            }
            Divider()
            if let error = state.error {
                Text(error).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal).padding(.top, 8).accessibilityAddTraits(.updatesFrequently)
            }
            HStack {
                Button("Open Config File…") { EditorLauncher.open(state.url) }
                Button("Reload") { state.reload() }
                Spacer()
                Button("Cancel") { NSApp.keyWindow?.close() }.keyboardShortcut(.cancelAction)
                Button("Save") { state.save() }.keyboardShortcut("s", modifiers: .command)
                    .disabled(state.error != nil && state.editUnavailable)
            }.padding()
        }
        .frame(minWidth: 620, idealWidth: 680, minHeight: 490, idealHeight: 550)
    }

    private var general: some View {
        Group {
            Section("Behavior") {
                Picker("Caps Lock", selection: $state.config.capsLock) {
                    Text("Unchanged").tag(CapsMode.default)
                    Text("Meh (Control–Option–Command)").tag(CapsMode.meh)
                    Text("Hyper (Control–Option–Shift–Command)").tag(CapsMode.hyper)
                }
                Text("In modifier modes, tap Caps Lock for Escape; hold it for the listed keys.").font(.caption).foregroundStyle(.secondary)
                Toggle("Stay Awake on launch", isOn: $state.config.caffeineOnLaunch)
                Text("The Stay Awake menu item controls only this session.").font(.caption).foregroundStyle(.secondary)
                Toggle("Launch at login", isOn: $state.config.launchAtLogin)
                Toggle("Check for updates automatically", isOn: $state.config.autoUpdate)
            }
            Section("Setup") {
                Button("Check Permissions…") { PrivilegesPresenter.present() }
                Button("Trackpad Setup…") { TrackpadSetup.present() }
            }
            Section("About") {
                Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"))")
                if let channel = Bundle.main.infoDictionary?["HyperMugReleaseChannel"] as? String ?? Bundle.main.infoDictionary?["ReleaseChannel"] as? String ?? Bundle.main.infoDictionary?["HyperMugChannel"] as? String {
                    Text("Channel: \(channel)")
                }
            }
        }
    }
    private var mouse: some View {
        Group {
            Section("Wheel scrolling") {
                Toggle("Reverse vertical wheel", isOn: $state.config.mouse.invertScroll.vertical)
                Toggle("Reverse horizontal wheel", isOn: $state.config.mouse.invertScroll.horizontal)
                Text("Applies to wheel mice, not trackpad or Magic Mouse scrolling.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Buttons") {
                ActionRow(title: "Back", key: "back", state: state)
                ActionRow(title: "Forward", key: "forward", state: state)
                ActionRow(title: "Thumb", key: "thumb", state: state)
                Text("Shortcuts use key names separated by +, spaces, or commas. Example: cmd + [.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var trackpad: some View {
        Group {
            ForEach([3, 4], id: \.self) { fingers in
                Section("\(fingers)-finger swipes") {
                    ForEach(SwipeDirection.allCases, id: \.rawValue) { direction in
                        ActionRow(title: direction.rawValue.capitalized, key: "\(fingers).\(direction.rawValue)", state: state)
                    }
                }
            }
            Section {
                Text("Disable conflicting macOS gestures in Trackpad settings before mapping these swipes.").font(.caption).foregroundStyle(.secondary)
                Button("Open Trackpad Setup…") { TrackpadSetup.present() }
            }
        }
    }
    private var helpers: some View {
        Section("Shared shell commands") {
            Text("Define a command once, then choose its name for mouse buttons or trackpad swipes.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach($state.helpers) { $helper in
                HStack {
                    TextField("Name", text: $helper.name).frame(width: 160)
                        .accessibilityLabel("Helper name")
                    TextField("Shell command", text: $helper.command)
                        .accessibilityLabel("Command for \(helper.name)")
                    Button("Remove", systemImage: "minus.circle") {
                        state.helpers.removeAll { $0.id == helper.id }
                    }.labelStyle(.iconOnly).accessibilityLabel("Remove helper \(helper.name)")
                }
            }
            Button("Add Helper") { state.helpers.append(HelperDraft(name: "", command: "")) }
        }
    }
}

private extension SettingsState { var editUnavailable: Bool { edit == nil } }

final class SettingsWindowController: NSWindowController {
    private let state: SettingsState
    init(url: URL) {
        let state = SettingsState(url: url)
        self.state = state
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 550),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "HyperMug Settings"
        window.contentView = NSHostingView(rootView: SettingsView(state: state))
        window.center()
        super.init(window: window)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func present() { state.reload(); showWindow(nil); NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil) }
}

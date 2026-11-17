import Foundation

/// Configuration document formats. TOML is canonical; JSON is the legacy format, migrated once.
public enum ConfigDocumentFormat: String, Equatable {
    case toml = "TOML"
    case json = "JSON"

    /// Schema and model validation; both formats share the value tree, so the messages are identical.
    public func validate(_ data: Data) -> Result<DecodedConfig, ConfigError> {
        self == .toml ? validateConfigTOML(data) : validateConfigDocument(data)
    }

    /// A new file shows every slot.
    func encode(_ config: AppConfig, schemaURL: URL?) -> Data {
        self == .toml ? encodeConfigTOML(config, schemaURL: schemaURL, includeEmptyKeys: true)
            : encodeConfig(config, schemaURL: schemaURL, includeEmptyKeys: true)
    }

    func linkingSchema(_ data: Data, schemaURL: URL) throws -> Data {
        self == .toml ? try tomlConfigDataLinkingSchema(data, schemaURL: schemaURL)
            : try configDataLinkingSchema(data, schemaURL: schemaURL)
    }

    var emptyDocumentReason: String {
        self == .toml ? "Configuration cannot be empty. Use a comment such as # defaults for default settings."
            : "Configuration cannot be empty. Use {} for default settings."
    }
}

/// Where the configuration came from, for the log and Doctor. File names only.
public enum ConfigNotice: Equatable {
    /// The legacy JSON file was converted; the original was renamed to `backup`.
    case migrated(from: String, to: String, backup: String)
    /// The legacy JSON file is invalid, so it was not converted and is still the active document.
    case migrationBlocked(from: String, to: String)
    /// Both files exist: the TOML file is used and the JSON file has no effect.
    case legacyIgnored(legacy: String, active: String)

    public var message: String {
        switch self {
        case .migrated(let from, let to, let backup):
            return "Migrated \(from) to \(to). The original is kept as \(backup)."
        case .migrationBlocked(let from, let to):
            return "\(from) was not migrated to \(to) because it is invalid. Fix it and \(AppIdentity.appName) migrates it automatically."
        case .legacyIgnored(let legacy, let active):
            return "\(legacy) is ignored because \(active) exists. Move or delete \(legacy)."
        }
    }
}

/// Everything the store needs from the OS, injected so the state machine stays deterministic and testable.
public struct ConfigStoreEnvironment {
    public var schemaURL: URL?
    public var readData: (URL) throws -> Data
    public var writeData: (Data, URL) throws -> Void
    /// Renames a migrated legacy file to its backup name.
    public var moveItem: (URL, URL) throws -> Void
    public var log: LogSink
    /// Runs `work` once on the main thread after `delay` seconds, unless cancelled first.
    public var schedule: (_ delay: TimeInterval, _ work: @escaping () -> Void) -> Cancellable
    /// Watches the file system object at `path` and calls `onEvent` on the main thread for every change.
    /// `gone` is true when the object itself was deleted, renamed away or revoked (the watch is dead then).
    /// Returns nil when the path cannot be watched.
    public var watch: (_ path: String, _ onEvent: @escaping (_ gone: Bool) -> Void) -> Cancellable?

    public init(
        schemaURL: URL? = nil,
        readData: @escaping (URL) throws -> Data = { try Data(contentsOf: $0) },
        writeData: @escaping (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) },
        moveItem: @escaping (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) },
        log: @escaping LogSink,
        schedule: @escaping (_ delay: TimeInterval, _ work: @escaping () -> Void) -> Cancellable,
        watch: @escaping (_ path: String, _ onEvent: @escaping (_ gone: Bool) -> Void) -> Cancellable?
    ) {
        self.schemaURL = schemaURL
        self.readData = readData
        self.writeData = writeData
        self.moveItem = moveItem
        self.log = log
        self.schedule = schedule
        self.watch = watch
    }
}

/// Owns the config: first-run creation, legacy JSON migration, schema-reference updates and live reload.
/// Automatic updates change only schema metadata; explicit editor saves compare the original bytes.
/// Main thread only.
public final class ConfigStore {
    /// The canonical document.
    public let url: URL
    public let format: ConfigDocumentFormat
    /// A legacy JSON document in the same directory, converted into `url` once while `url` does not exist.
    public let legacyURL: URL?
    /// The document that is read, watched and saved: the legacy JSON while it is invalid and not migrated.
    public var documentURL: URL { migrationPending ? legacyURL! : url }
    public var documentFormat: ConfigDocumentFormat { migrationPending ? .json : format }
    /// Latest migration or legacy-file notice.
    public private(set) var notice: ConfigNotice?
    /// Main thread; once per distinct notice.
    public var onNotice: ((ConfigNotice) -> Void)?
    /// Last good config.
    public private(set) var config = AppConfig()
    /// Non-nil while the file on disk is invalid.
    public private(set) var error: ConfigError?
    /// Unknown keys from the last valid file. These settings have no effect.
    public private(set) var unknownKeys: [String] = []
    /// Main thread; called whenever `config` changes after `start()`, and once from `start()`.
    public var onChange: ((AppConfig) -> Void)?
    /// Main thread; once per distinct reason while invalid (reset after a valid load).
    public var onError: ((ConfigError) -> Void)?

    private enum DiskState {
        case absent
        case data(Data)
        case unreadable(String)
    }

    private struct FileStamp: Equatable {
        let inode: UInt64?
        let mtime: Date?
        let size: UInt64?
    }

    private static let debounceSeconds: TimeInterval = 0.15

    private let env: ConfigStoreEnvironment
    private var started = false
    private var migrationPending = false
    /// Bytes of the file at the last load or write; identical bytes never reload.
    private var lastBytes: Data?
    private var lastStamp: FileStamp?
    private var lastAlertedReason: String?

    private var dirWatch: Cancellable?
    private var dirInode: UInt64?
    private var fileWatch: Cancellable?
    private var fileInode: UInt64?
    private var debounce: Cancellable?

    private var directoryURL: URL { url.deletingLastPathComponent() }
    /// Attribute lookups do not follow symlinks themselves, and a dotfiles setup symlinks the config.
    private var resolvedPath: String { documentURL.resolvingSymlinksInPath().path }

    public init(url: URL, format: ConfigDocumentFormat, legacyURL: URL? = nil, environment: ConfigStoreEnvironment) {
        self.url = url
        self.format = format
        self.legacyURL = legacyURL
        self.env = environment
    }

    // MARK: Public

    /// mkdir, migrate a legacy file, write defaults if absent, link the bundled schema, arm watchers, load,
    /// emit `onChange` once.
    public func start() {
        guard !started else { return }
        started = true
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            env.log(.error, "cannot create \(directoryURL.path): \(error.localizedDescription)")
        }
        migrateLegacyFile()
        if case .absent = readDisk() {
            if write(AppConfig.newFileDefaults) { config = .newFileDefaults }
        }
        armDirectoryWatcher()
        reload(emitChange: false)
        onChange?(config)
    }

    /// Settings…: recreates the file from the in-memory config if it is missing (deleted while running).
    /// Never touches an existing file, valid or not. Call after `start()`.
    public func createIfAbsent() {
        migrateLegacyFile()
        guard case .absent = readDisk() else { return }
        write(config)
        ensureFileWatcher()
    }

    /// Read the actual document, including an invalid one so it can be repaired in the app.
    public func readDocument() throws -> Data? {
        switch readDisk() {
        case .data(let data): return data
        case .absent: return nil
        case .unreadable(let reason): throw ConfigError(reason: reason)
        }
    }

    /// Editor validation of a whole document in the active document's format. A save rejects empty text.
    public func validateDocument(_ data: Data) -> Result<DecodedConfig, ConfigError> {
        guard !isBlankConfigData(data) else { return .failure(ConfigError(reason: documentFormat.emptyDocumentReason)) }
        return documentFormat.validate(data)
    }

    /// Save the raw document after validation and a byte comparison against the editor's baseline.
    /// The same store applies the result; the UI has no separate preferences representation.
    /// Fixing a legacy JSON document migrates it right away.
    public func saveDocument(_ data: Data, replacing expected: Data?) throws {
        let decoded = try validateDocument(data).get()
        let format = documentFormat
        let linked = try env.schemaURL.map { try format.linkingSchema(data, schemaURL: $0) } ?? data
        guard try readDocument() == expected else {
            throw ConfigError(reason: "The file changed on disk. Copy your draft if needed, then reload before saving.")
        }
        try env.writeData(linked, documentURL.resolvingSymlinksInPath())
        noteValid(linked)
        lastStamp = stamp()
        ensureFileWatcher()
        adopt(decoded.config, emitChange: true)
        if migrationPending { reload() }
    }

    /// Called by the 2 s timer: catches watcher misses and re-arms lost watchers.
    public func pollFallback() {
        guard started else { return }
        ensureDirectoryWatcher()
        ensureFileWatcher()
        if stamp() != lastStamp { reload() }
    }

    // MARK: Disk

    private func readDisk(_ file: URL? = nil) -> DiskState {
        let file = file ?? documentURL
        do {
            return .data(try env.readData(file))
        } catch let e as CocoaError where e.code == .fileReadNoSuchFile || e.code == .fileNoSuchFile {
            return .absent
        } catch {
            return .unreadable("cannot read \(file.path): \(error.localizedDescription)")
        }
    }

    /// Identity of the file system object at `path` (nil when it does not exist). Symlinks are not followed.
    private func attributes(ofPath path: String) -> FileStamp? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        return FileStamp(inode: a[.systemFileNumber] as? UInt64, mtime: a[.modificationDate] as? Date, size: a[.size] as? UInt64)
    }

    private func stamp() -> FileStamp? { attributes(ofPath: resolvedPath) }

    /// Atomic replace of the symlink target, so a dotfiles symlink stays a symlink.
    @discardableResult
    private func write(_ newConfig: AppConfig) -> Bool {
        let data = documentFormat.encode(newConfig, schemaURL: env.schemaURL)
        let target = documentURL.resolvingSymlinksInPath()
        do {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try env.writeData(data, target)
        } catch {
            env.log(.error, "cannot write \(target.path): \(error.localizedDescription)")
            return false
        }
        // Our own write must not look like an external edit, and the file on disk is valid now:
        // clear any stale invalid state so the same bad content alerts again if it comes back.
        noteValid(data)
        lastStamp = stamp()
        return true
    }

    // MARK: Migration

    /// Moves a legacy JSON document into the canonical file once: validate it, write the TOML atomically,
    /// then rename the JSON to a backup (never deleted). Invalid JSON is not migrated: it stays the active
    /// document, so it is reported and recovers exactly as before. With both files present, TOML wins.
    private func migrateLegacyFile() {
        guard let legacyURL else { return }
        let legacyName = legacyURL.lastPathComponent
        let name = url.lastPathComponent
        guard case .absent = readDisk(url) else {
            migrationPending = false
            if attributes(ofPath: legacyURL.path) != nil {
                announce(.legacyIgnored(legacy: legacyName, active: name))
            } else if case .legacyIgnored? = notice {
                notice = nil
            }
            return
        }
        let legacy = readDisk(legacyURL)
        if case .absent = legacy {
            migrationPending = false
            return
        }
        migrationPending = true
        guard case .data(let json) = legacy else { return }
        let converted: Data
        if isBlankConfigData(json) {
            converted = encodeConfigTOML(.newFileDefaults, schemaURL: env.schemaURL, includeEmptyKeys: true)
        } else {
            guard case .success = validateConfigDocument(json) else {
                announce(.migrationBlocked(from: legacyName, to: name))
                return
            }
            let toml = try! tomlConfigData(fromJSON: json)
            converted = env.schemaURL.map { try! tomlConfigDataLinkingSchema(toml, schemaURL: $0) } ?? toml
        }
        do {
            try env.writeData(converted, url.resolvingSymlinksInPath())
        } catch {
            env.log(.error, "cannot write \(url.path): \(error.localizedDescription); \(legacyName) stays active")
            return
        }
        migrationPending = false
        let backup = backupURL(for: legacyURL)
        do {
            try env.moveItem(legacyURL, backup)
            announce(.migrated(from: legacyName, to: name, backup: backup.lastPathComponent))
        } catch {
            env.log(.error, "cannot rename \(legacyName) to \(backup.lastPathComponent): \(error.localizedDescription)")
            announce(.legacyIgnored(legacy: legacyName, active: name))
        }
    }

    /// `hypermug.json.migrated-backup`, numbered when an earlier backup exists.
    private func backupURL(for legacy: URL) -> URL {
        func candidate(_ number: Int) -> URL {
            legacy.deletingLastPathComponent()
                .appendingPathComponent(legacy.lastPathComponent + ".migrated-backup" + (number > 1 ? "-\(number)" : ""))
        }
        var number = 1
        while attributes(ofPath: candidate(number).path) != nil { number += 1 }
        return candidate(number)
    }

    private func announce(_ newNotice: ConfigNotice) {
        guard newNotice != notice else { return }
        notice = newNotice
        env.log(.info, newNotice.message)
        onNotice?(newNotice)
    }

    // MARK: Load

    private func noteValid(_ data: Data) {
        error = nil
        unknownKeys = []
        lastAlertedReason = nil
        lastBytes = data
    }

    private func noteInvalid(_ data: Data?, _ e: ConfigError) {
        lastBytes = data
        error = e
        if e.reason != lastAlertedReason {
            env.log(.error, "invalid config: \(e.reason)")
            lastAlertedReason = e.reason
            onError?(e)
        }
    }

    /// Reload never replaces preferences: it links schema metadata and initializes only blank files.
    private func reload(emitChange: Bool = true) {
        debounce?.cancel()
        debounce = nil
        migrateLegacyFile()
        lastStamp = stamp()   // taken before reading: a change during the read shows up on the next poll
        switch readDisk() {
        case .absent:
            // Keep the last good config; recreated by `createIfAbsent`.
            lastBytes = nil
            error = nil
            lastAlertedReason = nil
            env.log(.info, "config file absent; keeping current settings")
        case .unreadable(let reason):
            noteInvalid(nil, ConfigError(reason: reason))
        case .data(let data):
            if data != lastBytes || error != nil {
                if isBlankConfigData(data) {
                    initializeEmptyFile(data, emitChange: emitChange)
                } else {
                    switch documentFormat.validate(data) {
                    case .success(let decoded):
                        guard let linked = linkSchema(data) else { break }
                        noteValid(linked)
                        unknownKeys = decoded.unknownKeys
                        adopt(decoded.config, emitChange: emitChange)
                    case .failure(let e):
                        noteInvalid(data, e)
                    }
                }
            }
        }
        ensureFileWatcher()
    }

    /// Metadata migration is the sole update to an existing nonempty file.
    /// The document is validated first; only its schema metadata changes.
    private func linkSchema(_ data: Data) -> Data? {
        guard let schemaURL = env.schemaURL,
              let linked = try? documentFormat.linkingSchema(data, schemaURL: schemaURL), linked != data else { return data }
        guard case .data(let current) = readDisk(), current == data else {
            scheduleReload()
            return nil
        }
        do {
            try env.writeData(linked, documentURL.resolvingSymlinksInPath())
            lastStamp = stamp()
            return linked
        } catch {
            noteInvalid(data, ConfigError(reason: "Cannot update the bundled schema reference: \(error.localizedDescription)"))
            return nil
        }
    }

    private func adopt(_ loaded: AppConfig, emitChange: Bool) {
        guard loaded != config else { return }
        config = loaded
        env.log(.info, "config reloaded")
        if emitChange { onChange?(config) }
    }

    /// Empty file = defaults, and the file gets initialized with them. The guarded write happens BEFORE
    /// adopting (onChange applies settings synchronously and can be slow, long enough for an editor to
    /// finish a save): re-read, and only if the file is still blank write the defaults; otherwise load
    /// what is there now and write nothing.
    private func initializeEmptyFile(_ data: Data, emitChange: Bool) {
        env.log(.info, "config file is empty; initializing it with defaults")
        guard case .data(let again) = readDisk(), isBlankConfigData(again) else {
            reload(emitChange: emitChange)
            return
        }
        if !write(AppConfig.newFileDefaults) {
            noteValid(data)   // don't retry a failing write on every reload
        }
        adopt(AppConfig.newFileDefaults, emitChange: emitChange)
    }

    private func scheduleReload() {
        debounce?.cancel()
        debounce = env.schedule(ConfigStore.debounceSeconds) { [weak self] in self?.reload() }
    }

    // MARK: Watchers

    /// Directory events cover create / rename-into-place / delete+recreate of the file.
    private func armDirectoryWatcher() {
        dirWatch?.cancel()
        dirWatch = nil
        dirInode = nil
        let path = directoryURL.path
        guard let watch = env.watch(path, { [weak self] gone in self?.directoryChanged(gone: gone) }) else {
            env.log(.error, "cannot watch \(path)")
            return
        }
        dirWatch = watch
        dirInode = attributes(ofPath: path)?.inode
    }

    private func directoryChanged(gone: Bool) {
        if gone {
            // The directory itself went away; pollFallback re-arms once it exists again.
            dirWatch?.cancel()
            dirWatch = nil
        }
        scheduleReload()
    }

    private func ensureDirectoryWatcher() {
        if dirWatch == nil || attributes(ofPath: directoryURL.path)?.inode != dirInode {
            armDirectoryWatcher()
        }
    }

    /// In-place writes (and the file vanishing) are seen through a watch on the file itself.
    private func ensureFileWatcher() {
        let current = attributes(ofPath: resolvedPath)?.inode
        if fileWatch != nil && current == fileInode { return }
        fileWatch?.cancel()
        fileWatch = nil
        fileInode = nil
        guard current != nil else { return }
        fileWatch = env.watch(documentURL.path) { [weak self] gone in self?.fileChanged(gone: gone) }
        fileInode = current
    }

    private func fileChanged(gone: Bool) {
        if gone {
            fileWatch?.cancel()
            fileWatch = nil
            fileInode = nil
        }
        scheduleReload()
    }
}

import Foundation

/// Everything the store needs from the OS, injected so the state machine stays deterministic and testable.
public struct ConfigStoreEnvironment {
    public var schemaURL: URL?
    public var readData: (URL) throws -> Data
    public var writeData: (Data, URL) throws -> Void
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
        log: @escaping LogSink,
        schedule: @escaping (_ delay: TimeInterval, _ work: @escaping () -> Void) -> Cancellable,
        watch: @escaping (_ path: String, _ onEvent: @escaping (_ gone: Bool) -> Void) -> Cancellable?
    ) {
        self.schemaURL = schemaURL
        self.readData = readData
        self.writeData = writeData
        self.log = log
        self.schedule = schedule
        self.watch = watch
    }
}

/// Owns the config: first-run creation, schema-reference migration and live reload.
/// Existing settings are never replaced; a migration changes only `$schema`.
/// Main thread only.
public final class ConfigStore {
    public let url: URL
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
    private var resolvedPath: String { url.resolvingSymlinksInPath().path }

    public init(url: URL, environment: ConfigStoreEnvironment) {
        self.url = url
        self.env = environment
    }

    // MARK: Public

    /// mkdir, write defaults if absent, link the bundled schema, arm watchers, load,
    /// emit `onChange` once.
    public func start() {
        guard !started else { return }
        started = true
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            env.log(.error, "cannot create \(directoryURL.path): \(error.localizedDescription)")
        }
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
        guard case .absent = readDisk() else { return }
        write(config)
        ensureFileWatcher()
    }

    /// Called by the 2 s timer: catches watcher misses and re-arms lost watchers.
    public func pollFallback() {
        guard started else { return }
        ensureDirectoryWatcher()
        ensureFileWatcher()
        if stamp() != lastStamp { reload() }
    }

    // MARK: Disk

    private func readDisk() -> DiskState {
        do {
            return .data(try env.readData(url))
        } catch let e as CocoaError where e.code == .fileReadNoSuchFile || e.code == .fileNoSuchFile {
            return .absent
        } catch {
            return .unreadable("cannot read \(url.path): \(error.localizedDescription)")
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
        let data = encodeConfig(newConfig, schemaURL: env.schemaURL, includeEmptyKeys: true)
        let target = url.resolvingSymlinksInPath()
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

    /// Loads the file. The only write it ever does is filling a file that is still empty with the defaults.
    private func reload(emitChange: Bool = true) {
        debounce?.cancel()
        debounce = nil
        lastStamp = stamp()   // taken before reading: a change during the read shows up on the next poll
        switch readDisk() {
        case .absent:
            // Keep the last good config; recreated by `createIfAbsent`.
            lastBytes = nil
            error = nil
            env.log(.info, "config file absent; keeping current settings")
        case .unreadable(let reason):
            noteInvalid(nil, ConfigError(reason: reason))
        case .data(let data):
            if data != lastBytes || error != nil {
                if isBlankConfigData(data) {
                    initializeEmptyFile(data, emitChange: emitChange)
                } else {
                    switch validateConfigDocument(data) {
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
    /// Invalid JSON is left untouched so the normal decoder can report it.
    private func linkSchema(_ data: Data) -> Data? {
        guard let schemaURL = env.schemaURL,
              let linked = try? configDataLinkingSchema(data, schemaURL: schemaURL), linked != data else { return data }
        guard case .data(let current) = readDisk(), current == data else {
            scheduleReload()
            return nil
        }
        do {
            try env.writeData(linked, url.resolvingSymlinksInPath())
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
        fileWatch = env.watch(url.path) { [weak self] gone in self?.fileChanged(gone: gone) }
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

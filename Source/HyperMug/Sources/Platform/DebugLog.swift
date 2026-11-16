import Foundation
import HyperMugCore

/// `~/Library/Logs/HyperMug/debug.log`: readable without unified-log permission. Keeps the previous session.
/// Writes happen on a utility queue, so callers (the event tap callback) never wait on disk.
/// Line format and the size budget are Core (`debugLogLine`, `DebugLogBudget`).
final class DebugLog {
    private static let queue = DispatchQueue(label: "\(AppIdentity.bundleID).debuglog", qos: .utility)
    private static let log = makeLogSink(category: "debuglog")
    private static var handle: FileHandle?
    private static var budget = DebugLogBudget()
    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(AppIdentity.debugLogDirectory, isDirectory: true)
            .appendingPathComponent("debug.log")
    }

    static func recentText() -> String {
        queue.sync {
            guard let data = try? Data(contentsOf: fileURL) else { return "Log unavailable." }
            return String(decoding: data, as: UTF8.self).split(separator: "\n").suffix(80).joined(separator: "\n")
        }
    }
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    /// Creates the log directory and file, emptying any previous content. Call once at app start.
    static func reset() {
        queue.sync {
            handle = nil
            budget.reset()
            let dir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(AppIdentity.debugLogDirectory, isDirectory: true)
            let file = dir.appendingPathComponent("debug.log")
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let previous = dir.appendingPathComponent("previous.log")
                if FileManager.default.fileExists(atPath: file.path) {
                    try? FileManager.default.removeItem(at: previous)
                    try FileManager.default.moveItem(at: file, to: previous)
                }
                guard FileManager.default.createFile(atPath: file.path, contents: nil) else { return }
                handle = try FileHandle(forWritingTo: file)
            } catch {
                log(.error, "debug log unavailable: \(error.localizedDescription)")
            }
        }
    }

    /// Appends one timestamped line. Never log keycodes or characters of typed keys.
    static func write(_ line: String) {
        let now = Date()
        queue.async {
            guard let handle else { return }
            let data = Data(debugLogLine(line, timestamp: formatter.string(from: now)).utf8)
            if budget.admit(byteCount: data.count) {
                try? handle.truncate(atOffset: 0)
                try? handle.seek(toOffset: 0)
            }
            try? handle.write(contentsOf: data)
        }
    }
}

import Foundation
import HyperMugCore

/// Removes a leftover Caps→F18 `hidutil` mapping from older MyMug builds. Other user mappings stay untouched.
/// What to remove is Core (`legacyCapsRemapCleanup`); this only runs hidutil.
enum LegacyCapsRemap {
    static func removeIfPresent(log: LogSink) {
        let output = runHidutil(["--get", "UserKeyMapping"], log: log)
        guard let json = legacyCapsRemapCleanup(hidutilOutput: output) else { return }
        _ = runHidutil(["--set", json], log: log)
        log(.info, "removed leftover Caps→F18 mapping")
        DebugLog.write("removed leftover Caps→F18 mapping")
    }

    /// Runs hidutil and returns its stdout (empty on failure).
    private static func runHidutil(_ arguments: [String], log: LogSink) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = ["property"] + arguments
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
        } catch {
            log(.error, "hidutil failed: \(error.localizedDescription)")
            return ""
        }
    }
}

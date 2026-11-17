import AppKit
import HyperMugCore

let appURL = URL(fileURLWithPath: CommandLine.arguments[1])
let manager = FileManager.default
let aerospacePath = ["/opt/homebrew/bin/aerospace", "/usr/local/bin/aerospace"]
    .first { manager.isExecutableFile(atPath: $0) }
func aerospace(_ arguments: [String]) -> String? {
    guard let aerospacePath else { return nil }
    let command = Process()
    command.executableURL = URL(fileURLWithPath: aerospacePath)
    command.arguments = arguments
    command.standardInput = FileHandle.nullDevice
    command.standardError = FileHandle.nullDevice
    let output = Pipe()
    command.standardOutput = output
    do { try command.run() } catch { return nil }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    command.waitUntilExit()
    guard command.terminationStatus == 0 else { return nil }
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}
let currentWorkspace = aerospace(["list-workspaces", "--focused"])
let directory = manager.homeDirectoryForCurrentUser.appendingPathComponent(".config", isDirectory: true)
let devConfig = directory.appendingPathComponent("hypermug-dev.toml")
let devLegacyConfig = directory.appendingPathComponent("hypermug-dev.json")
let productionConfig = directory.appendingPathComponent("hypermug.toml")
let productionLegacyConfig = directory.appendingPathComponent("hypermug.json")

// Copy settings once. Later Dev edits never change the production file, which is only read here (Dev
// migrates its own legacy hypermug-dev.json itself).
if !manager.fileExists(atPath: devConfig.path), !manager.fileExists(atPath: devLegacyConfig.path) {
    var source: [String: ConfigValue]?
    if manager.fileExists(atPath: productionConfig.path) {
        source = try parseConfigTOML(Data(contentsOf: productionConfig)).get()
    } else if manager.fileExists(atPath: productionLegacyConfig.path) {
        source = try parseConfigTOML(tomlConfigData(fromJSON: Data(contentsOf: productionLegacyConfig))).get()
    }
    if var config = source {
        config["$schema"] = .string(appURL.appendingPathComponent("Contents/Resources/hypermug-dev.schema.json").absoluteString)
        config["launchAtLogin"] = .boolean(false)
        config.removeValue(forKey: "autoUpdate")
        try renderConfigTOML(config).write(to: devConfig, options: .atomic)
        print("Created separate Dev settings: \(devConfig.path)")
    }
}

// Restart only Dev. Production and Dev have separate identities and settings.
let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.maxmeis.hypermug.dev")
for app in running {
    guard app.terminate() else {
        fputs("Could not stop \(app.localizedName ?? "HyperMug Dev"). Quit it before starting Dev.\n", stderr)
        exit(1)
    }
}
let deadline = Date().addingTimeInterval(8)
while running.contains(where: { !$0.isTerminated }), Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
}
guard running.allSatisfy({ $0.isTerminated }) else {
    fputs("HyperMug Dev has not stopped. Dev was not started.\n", stderr)
    exit(1)
}

let configuration = NSWorkspace.OpenConfiguration()
configuration.arguments = ["--doctor"]
configuration.activates = true
var finished = false
var status: Int32 = 0
NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { app, error in
    if let error {
        fputs("Could not start HyperMug Dev: \(error.localizedDescription)\n", stderr)
        status = 1
    } else {
        print("Started HyperMug Dev (PID \(app?.processIdentifier ?? 0)). Doctor is opening.")
    }
    finished = true
}
while !finished { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
// AeroSpace rules can move a new utility window to a hidden workspace.
// Keep Doctor on the workspace from which this local launch was requested.
if status == 0, let currentWorkspace, !currentWorkspace.isEmpty {
    let deadline = Date().addingTimeInterval(5)
    var doctorWindow: String?
    repeat {
        let windows = aerospace(["list-windows", "--all", "--format", "%{window-id}|%{app-bundle-id}"]) ?? ""
        doctorWindow = windows.split(separator: "\n").compactMap { line -> String? in
            let fields = line.split(separator: "|")
            guard fields.count == 2, fields[1] == "com.maxmeis.hypermug.dev" else { return nil }
            return String(fields[0])
        }.first
        if doctorWindow == nil { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
    } while doctorWindow == nil && Date() < deadline
    if let doctorWindow {
        if aerospace(["move-node-to-workspace", "--window-id", doctorWindow, currentWorkspace]) != nil {
            _ = aerospace(["focus", "--window-id", doctorWindow])
            print("Doctor is on workspace \(currentWorkspace).")
        }
    } else {
        fputs("Doctor did not appear in AeroSpace within 5 seconds. Check the Dev log.\n", stderr)
        status = 1
    }
}
exit(status)

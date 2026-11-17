import AppKit
import Carbon.HIToolbox
import Darwin
import HyperMugCore
import IOKit

/// Reads Secure Event Input state and process facts from the OS, and asks a process to quit.
/// Decisions (holder choice, names, protection) live in Core; this only turns OS calls into plain values.
enum SecureInputReader {
    /// This process, for `protectionReason(_:selfPID:currentUID:)`.
    static let selfPID = ProcessInfo.processInfo.processIdentifier
    /// The current user, for `protectionReason(_:selfPID:currentUID:)`.
    static let currentUID = getuid()

    /// nil when Secure Event Input is off. Cheap flag first; the IORegistry is read only when it is on.
    static func current() -> SecureInputInfo? {
        guard IsSecureEventInputEnabled() else { return nil }
        return secureInputInfo(
            sessions: parseConsoleUsers(consoleUsers()), currentUID: currentUID, resolve: facts(pid:))
    }

    /// Fresh process facts for `pid`. Also used to re-check a holder right before a destructive action.
    static func facts(pid: Int32) -> ProcessFacts {
        let app = NSRunningApplication(processIdentifier: pid)
        let ownerUID = processOwnerUID(pid: pid)
        return ProcessFacts(
            pid: pid, exists: processExists(pid: pid),
            localizedName: app?.localizedName,
            processName: kernelProcessName(pid: pid),
            bundleID: app?.bundleIdentifier,
            bundlePath: app?.bundleURL?.path,
            executablePath: app?.executableURL?.path,
            kernelPath: kernelProcessPath(pid: pid),
            ownerName: ownerUID.flatMap(userName(uid:)),
            ownerUID: ownerUID,
            isFrontmost: NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
            hasApp: app != nil)
    }

    static func activate(pid: Int32) {
        NSRunningApplication(processIdentifier: pid)?.activate()
    }

    /// Asks the process to quit (or kills it). Returns the OS error text when that failed, nil on success.
    static func terminate(pid: Int32, force: Bool) -> String? {
        if let app = NSRunningApplication(processIdentifier: pid) {
            let accepted = force ? app.forceTerminate() : app.terminate()
            if accepted { return nil }
        }
        if kill(pid, terminationSignal(force: force)) != 0 {
            return String(cString: strerror(errno))
        }
        return nil
    }

    // MARK: - IORegistry

    /// All `IOConsoleUsers` entries of the IORegistry root.
    private static func consoleUsers() -> [[String: Any]] {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != 0 else { return [] }
        defer { IOObjectRelease(root) }
        guard let property = IORegistryEntryCreateCFProperty(root, "IOConsoleUsers" as CFString, kCFAllocatorDefault, 0)
        else { return [] }
        return property.takeRetainedValue() as? [[String: Any]] ?? []
    }

    // MARK: - Process facts

    private static func kernelProcessName(pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 256)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    /// A stale IOConsoleUsers PID must not be presented as a process that HyperMug can terminate.
    private static func processExists(pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }

    private static func kernelProcessPath(pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    private static func processOwnerUID(pid: Int32) -> UInt32? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return info.pbi_uid
    }

    private static func userName(uid: UInt32) -> String? {
        guard let entry = getpwuid(uid) else { return nil }
        return String(cString: entry.pointee.pw_name)
    }
}

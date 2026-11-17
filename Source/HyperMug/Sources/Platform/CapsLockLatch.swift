import IOKit.hidsystem

/// Clears the system latch without changing modifier-key preferences or HID mappings.
enum CapsLockLatch {
    /// `force` skips the read-back: the caller saw Caps Lock latched in an event, and the lock state read through
    /// IOHIDSystem can lag the event stream. Returns true when a clear was issued (or the state could not be read).
    static func clear(force: Bool) -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        guard service != 0 else { DebugLog.write("Caps Lock reset: IOHIDSystem unavailable"); return true }
        defer { IOObjectRelease(service) }
        var connection: io_connect_t = 0
        let opened = IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connection)
        guard opened == KERN_SUCCESS else { DebugLog.write("Caps Lock reset: open failed code=\(opened)"); return true }
        defer { IOServiceClose(connection) }
        var locked = false
        let read = IOHIDGetModifierLockState(connection, Int32(kIOHIDCapsLockState), &locked)
        if read != KERN_SUCCESS { DebugLog.write("Caps Lock reset: read failed code=\(read)") }
        guard force || locked || read != KERN_SUCCESS else { return false }
        let result = IOHIDSetModifierLockState(connection, Int32(kIOHIDCapsLockState), false)
        DebugLog.write("Caps Lock latch cleared force=\(force) read=\(locked) result=\(result)")
        return true
    }
}

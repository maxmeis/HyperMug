import IOKit.hidsystem

/// Clears the system latch without changing modifier-key preferences or HID mappings.
enum CapsLockLatch {
    static func clear() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        guard service != 0 else { DebugLog.write("Caps Lock reset: IOHIDSystem unavailable"); return }
        defer { IOObjectRelease(service) }
        var connection: io_connect_t = 0
        let opened = IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connection)
        guard opened == KERN_SUCCESS else { DebugLog.write("Caps Lock reset: open failed code=\(opened)"); return }
        defer { IOServiceClose(connection) }
        var locked = false
        let read = IOHIDGetModifierLockState(connection, Int32(kIOHIDCapsLockState), &locked)
        guard read == KERN_SUCCESS else { DebugLog.write("Caps Lock reset: read failed code=\(read)"); return }
        guard locked else { return }
        let result = IOHIDSetModifierLockState(connection, Int32(kIOHIDCapsLockState), false)
        DebugLog.write("Caps Lock latch cleared result=\(result)")
    }
}

import Foundation
@testable import HyperMugCore

func capsMonitorTests() {
    // Closed and enabled: open.
    var policy = CapsMonitorPolicy()
    expectEqual(policy.setEnabled(true, isOpen: false, access: .granted), .open)
    // Open and still enabled: nothing to do.
    expectEqual(policy.setEnabled(true, isOpen: true, access: .granted), .none)

    // After a failed attempt, no retry while Input Monitoring is not granted ...
    policy = CapsMonitorPolicy()
    expectEqual(policy.setEnabled(true, isOpen: false, access: .denied), .open)
    expectEqual(policy.setEnabled(true, isOpen: false, access: .denied), .none)
    expectEqual(policy.setEnabled(true, isOpen: false, access: .unknown), .none)
    // ... but once it is granted, the next sync retries.
    expectEqual(policy.setEnabled(true, isOpen: false, access: .granted), .open)
    // The first attempt is made whatever the access state says (the open itself triggers/permits the check).
    policy = CapsMonitorPolicy()
    expectEqual(policy.setEnabled(true, isOpen: false, access: .unknown), .open)

    // Disable: close only when open.
    policy = CapsMonitorPolicy()
    expectEqual(policy.setEnabled(false, isOpen: true, access: .granted), .close)
    expectEqual(policy.setEnabled(false, isOpen: false, access: .granted), .none)
    expectEqual(policy.setEnabled(false, isOpen: false, access: .denied), .none)

    // Open result lines: only when the result changes.
    policy = CapsMonitorPolicy()
    expectEqual(policy.openFinished(code: 0), "caps hid open ok=true result=0")
    expect(policy.openFinished(code: 0) == nil, "same result is not logged again")
    // IOReturn codes are shown as unsigned hex (kIOReturnNotPermitted).
    expectEqual(policy.openFinished(code: Int32(bitPattern: 0xE00002E2)), "caps hid open ok=false result=e00002e2")
    expect(policy.openFinished(code: Int32(bitPattern: 0xE00002E2)) == nil, "repeated failure is not logged again")
    expectEqual(policy.openFinished(code: 0), "caps hid open ok=true result=0")

    // Closing an open monitor forgets the last result, so the next open is logged again.
    policy = CapsMonitorPolicy()
    _ = policy.openFinished(code: 0)
    _ = policy.setEnabled(false, isOpen: true, access: .granted)
    expectEqual(policy.openFinished(code: 0), "caps hid open ok=true result=0")

    // Closing something that was not open keeps the dedup (a failing open must not spam every sync).
    policy = CapsMonitorPolicy()
    _ = policy.openFinished(code: Int32(bitPattern: 0xE00002E2))
    _ = policy.setEnabled(false, isOpen: false, access: .denied)
    expect(policy.openFinished(code: Int32(bitPattern: 0xE00002E2)) == nil, "failed result stays deduplicated")
}

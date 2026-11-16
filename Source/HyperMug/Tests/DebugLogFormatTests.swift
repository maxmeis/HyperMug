import Foundation
@testable import HyperMugCore

func debugLogFormatTests() {
    expectEqual(debugLogLine("caps down", timestamp: "12:34:56.789"), "12:34:56.789 caps down\n")
    expectEqual(debugLogLine("", timestamp: "00:00:00.000"), "00:00:00.000 \n")

    // Lines are admitted until the next one would exceed the limit; then the file is truncated first.
    var budget = DebugLogBudget(maxBytes: 100)
    expect(!budget.admit(byteCount: 40), "first line fits")
    expect(!budget.admit(byteCount: 60), "exactly at the limit still fits")
    expect(budget.admit(byteCount: 1), "one byte over: truncate first")
    // After a truncation the new line counts from zero.
    expect(!budget.admit(byteCount: 99), "99 + 1 fits after the truncation")
    expect(!budget.admit(byteCount: 0), "an empty write never truncates")
    expect(budget.admit(byteCount: 1), "100 bytes used, one more: truncate again")

    // A reset (file emptied at app start) starts counting from zero.
    budget = DebugLogBudget(maxBytes: 10)
    _ = budget.admit(byteCount: 10)
    budget.reset()
    expect(!budget.admit(byteCount: 10), "fits after reset")

    // A single line larger than the whole budget still gets written (after a truncation), never dropped.
    budget = DebugLogBudget(maxBytes: 10)
    expect(budget.admit(byteCount: 50), "oversized line truncates")
    expect(budget.admit(byteCount: 1), "and the budget stays exceeded for the next line")

    // Default budget is about 1 MB.
    var standard = DebugLogBudget()
    expect(!standard.admit(byteCount: 1_000_000), "1 MB fits")
    expect(standard.admit(byteCount: 1), "past 1 MB truncates")
}

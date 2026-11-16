@testable import HyperMugCore

func supportTests() {
    modalGateTests()
    alertQueueTests()
}

private func modalGateTests() {
    var gate = ModalGate()
    expect(gate.tryEnter(), "first enter succeeds")
    expect(!gate.tryEnter(), "second enter is refused while inside")
    expect(!gate.tryEnter(), "still refused")
    gate.leave()
    expect(gate.tryEnter(), "leave re-opens the gate")
    expect(!gate.tryEnter(), "and it closes again after the new enter")

    var idle = ModalGate()
    idle.leave()
    expect(idle.tryEnter(), "leave without a prior enter changes nothing")
}

private func alertQueueTests() {
    // First arrival is shown right away.
    var queue = AlertQueue<String>()
    expectEqual(queue.arrive("a"), "a", "first arrival shows")

    // Arrivals while showing are held back; only the latest is kept.
    expectEqual(queue.arrive("b"), nil, "queued while showing")
    expectEqual(queue.arrive("c"), nil, "queued while showing")
    expectEqual(queue.dismissed(stillCurrent: "c"), "c", "latest pending item is shown next")

    // The returned item counts as showing: a new arrival must wait.
    expectEqual(queue.arrive("d"), nil, "the next item is showing, so a new one waits")
    expectEqual(queue.dismissed(stillCurrent: "d"), "d", "and shows after that dismissal")

    // Nothing pending: dismissal returns nil and the next arrival shows again.
    expectEqual(queue.dismissed(stillCurrent: "d"), nil, "nothing pending after the last dismissal")
    expectEqual(queue.arrive("e"), "e", "queue is idle again")

    // A pending item that is no longer current is dropped, and not remembered afterwards.
    expectEqual(queue.arrive("stale"), nil, "queued while showing")
    expectEqual(queue.dismissed(stillCurrent: "other"), nil, "stale pending item is dropped")
    expectEqual(queue.arrive("f"), "f", "queue is idle after dropping the stale item")
    expectEqual(queue.dismissed(stillCurrent: "f"), nil, "dropped item does not come back")

    // Pending item with no current item at all (error cleared meanwhile).
    expectEqual(queue.arrive("g"), "g", "shows")
    expectEqual(queue.arrive("h"), nil, "queued")
    expectEqual(queue.dismissed(stillCurrent: nil), nil, "no current item: nothing is shown")
}

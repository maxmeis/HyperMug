@testable import HyperMugCore

private func contacts(_ n: Int, _ dx: Double = 0, _ dy: Double = 0, state: Int32 = 4) -> [TrackpadContact] {
    (0..<n).map { i in TrackpadContact(identifier: Int32(i), state: state,
                                      x: 0.25 + Double(i) * 0.1 + dx, y: 0.4 + dy) }
}

private func mapped(_ fingers: Int, _ direction: SwipeDirection) -> TrackpadConfig {
    var map = SwipeMap()
    let action = ButtonAction.shell("true")
    switch direction {
    case .up: map.up = action
    case .down: map.down = action
    case .left: map.left = action
    case .right: map.right = action
    }
    return fingers == 3 ? TrackpadConfig(threeFingerSwipe: map) : TrackpadConfig(fourFingerSwipe: map)
}

private func feed(_ state: inout TrackpadSwipeState, _ contacts: [TrackpadContact], _ time: Double,
                  device: UInt64 = 1) -> TrackpadSwipe? {
    state.handleFrame(device: device, contacts: contacts, timestamp: time)
}

func trackpadSwipesTests() {
    for fingers in [3, 4] {
        for direction in SwipeDirection.allCases {
            var state = TrackpadSwipeState(config: mapped(fingers, direction))
            let delta: (Double, Double)
            switch direction {
            case .up: delta = (0, 1)
            case .down: delta = (0, -1)
            case .left: delta = (-1, 0)
            case .right: delta = (1, 0)
            }
            expectEqual(feed(&state, contacts(fingers), 0), nil)
            expectEqual(feed(&state, contacts(fingers), 0.01), nil)
            expectEqual(feed(&state, contacts(fingers, delta.0 * 0.02, delta.1 * 0.02), 0.02), nil)
            expectEqual(feed(&state, contacts(fingers, delta.0 * 0.06, delta.1 * 0.06), 0.03), nil)
            expectEqual(feed(&state, contacts(fingers, delta.0 * 0.09, delta.1 * 0.09), 0.04),
                        TrackpadSwipe(fingers: fingers, direction: direction))
            expectEqual(feed(&state, contacts(fingers, delta.0 * 0.14, delta.1 * 0.14), 0.05), nil, "one shot")
            expectEqual(feed(&state, [], 0.06), nil)
        }
    }
    var state = TrackpadSwipeState(config: mapped(3, .right))
    expectEqual(feed(&state, contacts(3, state: 2), 0), nil, "hover ignored")
    expectEqual(feed(&state, contacts(3, state: 5), 0.01), nil, "lift ignored")
    expectEqual(feed(&state, contacts(3), 0.02), nil)
    expectEqual(feed(&state, contacts(3), 0.03), nil)
    expectEqual(feed(&state, contacts(3, 0.005), 0.04), nil, "noise")
    expectEqual(feed(&state, contacts(3, 0.05), 0.05), nil)
    expectEqual(feed(&state, contacts(3, 0.09), 0.06), TrackpadSwipe(fingers: 3, direction: .right))
    expectEqual(feed(&state, contacts(2), 0.07), nil)
    expectEqual(feed(&state, [], 0.08), nil)

    state.reset()
    expectEqual(feed(&state, contacts(3), 1), nil)
    expectEqual(feed(&state, contacts(3), 1.01), nil)
    expectEqual(feed(&state, contacts(3, -0.04), 1.02), nil, "unmapped direction")
    expectEqual(feed(&state, contacts(3, -0.09), 1.03), nil)
    expectEqual(feed(&state, [], 1.04), nil)
    state.apply(mapped(4, .up))
    expectEqual(feed(&state, contacts(3), 2), nil, "unmapped count")
    expectEqual(feed(&state, contacts(3, 0.09), 2.01), nil)
    state.removeDevice(1)
    expectEqual(feed(&state, contacts(4), 3), nil)
    expectEqual(feed(&state, contacts(4), 3.01), nil)
    expectEqual(feed(&state, contacts(4, 0, 0.04), 3.02), nil)
    state.apply(mapped(3, .right))

    // A fourth finger may land before travel; after travel a changed identity cancels the stroke.
    expectEqual(feed(&state, contacts(3), 4), nil)
    expectEqual(feed(&state, contacts(4), 4.01), nil)
    expectEqual(feed(&state, contacts(4), 4.02), nil)
    expectEqual(feed(&state, contacts(4, 0.09), 4.03), nil, "four unmapped")
    state.reset()
    expectEqual(feed(&state, contacts(3), 5), nil)
    expectEqual(feed(&state, contacts(3), 5.01), nil)
    expectEqual(feed(&state, contacts(3, 0.02), 5.02), nil)
    expectEqual(feed(&state, contacts(4, 0.03), 5.03), nil)
    expectEqual(feed(&state, contacts(3, 0.10), 5.04), nil, "count change stays cancelled")

    state.reset()
    expectEqual(feed(&state, contacts(3), 6), nil)
    expectEqual(feed(&state, contacts(3), 6.01), nil)
    var pinch = contacts(3)
    pinch[0] = TrackpadContact(identifier: 0, state: 4, x: 0.16, y: 0.4)
    pinch[2] = TrackpadContact(identifier: 2, state: 4, x: 0.54, y: 0.4)
    expectEqual(feed(&state, pinch, 6.02), nil, "pinch")
    expectEqual(feed(&state, contacts(5), 6.03), nil, "five fingers")
    expectEqual(feed(&state, contacts(3, 0.1), 6.04), nil, "blocked after five")

    state.reset()
    expectEqual(feed(&state, contacts(3), 7, device: 10), nil)
    expectEqual(feed(&state, contacts(3), 7.01, device: 10), nil)
    expectEqual(feed(&state, contacts(3, 0.04), 7.02, device: 10), nil)
    expectEqual(feed(&state, contacts(3), 7.03, device: 11), nil)
    expectEqual(feed(&state, contacts(3, 0.09), 7.04, device: 10), TrackpadSwipe(fingers: 3, direction: .right))
    state.removeDevice(10)
    expectEqual(feed(&state, contacts(3), 7.05, device: 11), nil)
    expectEqual(feed(&state, contacts(3, 0.04), 7.06, device: 11), nil)
    expectEqual(feed(&state, contacts(3, 0.09), 7.07, device: 11), TrackpadSwipe(fingers: 3, direction: .right))
    expectEqual(feed(&state, contacts(3, 0.11), 7.06, device: 11), nil, "stale frame ignored")
    expectEqual(feed(&state, [TrackpadContact(identifier: 1, state: 4, x: .nan, y: 0)], 8), nil)
    expectEqual(feed(&state, [TrackpadContact(identifier: 1, state: 4, x: 0.2, y: 0.4),
                               TrackpadContact(identifier: 1, state: 4, x: 0.3, y: 0.4)], 8.1), nil,
                "duplicate identity")
    expectEqual(feed(&state, contacts(3, 0.8), 8.2), nil, "out of bounds")
    expectEqual(feed(&state, contacts(3), .infinity), nil)

    state.reset()
    expectEqual(feed(&state, contacts(2), 9), nil, "staggered start")
    expectEqual(feed(&state, contacts(3), 9.01), nil)
    expectEqual(feed(&state, contacts(3), 9.02), nil)
    expectEqual(feed(&state, contacts(3, 0.04, 0.005), 9.03), nil)
    expectEqual(feed(&state, contacts(3, 0.09, 0.009), 9.04),
                TrackpadSwipe(fingers: 3, direction: .right), "minor drift allowed")
    state.reset()
    expectEqual(feed(&state, contacts(3), 10), nil)
    expectEqual(feed(&state, contacts(3), 10.01), nil)
    expectEqual(feed(&state, contacts(3, 0.04), 10.02), nil)
    expectEqual(feed(&state, contacts(3, -0.01), 10.03), nil, "reversal cancels net travel")
    // Repeated Engine config syncs preserve both a partial stroke and its one-shot latch.
    var sync = TrackpadSwipeState(config: mapped(3, .right))
    expectEqual(feed(&sync, contacts(3), 11), nil)
    expectEqual(feed(&sync, contacts(3), 11.01), nil)
    expectEqual(feed(&sync, contacts(3, 0.04), 11.02), nil)
    sync.apply(mapped(3, .right))
    expectEqual(feed(&sync, contacts(3, 0.09), 11.03), TrackpadSwipe(fingers: 3, direction: .right))
    sync.apply(mapped(3, .right))
    expectEqual(feed(&sync, contacts(3, 0.14), 11.04), nil, "same config cannot re-arm")
    expectEqual(feed(&sync, contacts(3, 0.17), 11.03), nil, "stale active frame ignored")
    expectEqual(feed(&sync, contacts(3, 0.19), 11.05), nil, "still one shot")
    expectEqual(feed(&sync, [], 11.06), nil)
    expectEqual(feed(&sync, contacts(3, 0.20), 11.055), nil, "stale frame after lift")
    expectEqual(feed(&sync, contacts(3), 11.07), nil)
    expectEqual(feed(&sync, contacts(3), 11.08), nil)
    expectEqual(feed(&sync, contacts(3, 0.04), 11.09), nil)
    expectEqual(feed(&sync, contacts(3, 0.09), 11.10), TrackpadSwipe(fingers: 3, direction: .right))

    // A changed config blocks the current sequence, even if the same fingers move
    // through a mapped direction after the reload.
    var reload = TrackpadSwipeState(config: mapped(3, .left))
    expectEqual(feed(&reload, contacts(3), 12), nil)
    expectEqual(feed(&reload, contacts(3), 12.01), nil)
    reload.apply(mapped(3, .right))
    expectEqual(feed(&reload, contacts(3, 0.04), 12.02), nil)
    expectEqual(feed(&reload, contacts(3, 0.09), 12.03), nil)
    reload.apply(mapped(3, .right))
    expectEqual(feed(&reload, contacts(3, 0.14), 12.04), nil)
    expectEqual(feed(&reload, [], 12.05), nil)
    expectEqual(feed(&reload, contacts(3), 12.06), nil)
    expectEqual(feed(&reload, contacts(3), 12.07), nil)
    expectEqual(feed(&reload, contacts(3, 0.04), 12.08), nil)
    expectEqual(feed(&reload, contacts(3, 0.09), 12.09), TrackpadSwipe(fingers: 3, direction: .right))

    // Frame clocks are independent, including while one device is active or lifted.
    var independent = TrackpadSwipeState(config: mapped(3, .right))
    expectEqual(feed(&independent, contacts(3), 100, device: 21), nil)
    expectEqual(feed(&independent, contacts(3), 1, device: 22), nil)
    expectEqual(feed(&independent, contacts(3), 100.01, device: 21), nil)
    expectEqual(feed(&independent, contacts(3), 1.01, device: 22), nil)
    expectEqual(feed(&independent, contacts(3, 0.04), 100.02, device: 21), nil)
    expectEqual(feed(&independent, contacts(3, 0.04), 1.02, device: 22), nil)
    expectEqual(feed(&independent, contacts(3, 0.09), 1.03, device: 22), TrackpadSwipe(fingers: 3, direction: .right))
    expectEqual(feed(&independent, contacts(3, 0.09), 100.03, device: 21), TrackpadSwipe(fingers: 3, direction: .right))
    expectEqual(feed(&independent, [], 1.04, device: 22), nil)
    expectEqual(feed(&independent, contacts(3), 1.035, device: 22), nil, "stale after lift")
    expectEqual(feed(&independent, contacts(3, 0.13), 100.04, device: 21), nil, "other latch survives")
    independent.removeDevice(22)
    expectEqual(feed(&independent, contacts(3), 0.5, device: 22), nil, "reconnect clock resets")

    // Invalid active frames block until lift, preserving the one-shot boundary.
    var invalid = TrackpadSwipeState(config: mapped(3, .right))
    expectEqual(feed(&invalid, contacts(3), 13), nil)
    expectEqual(feed(&invalid, contacts(3), 13.01), nil)
    expectEqual(feed(&invalid, [TrackpadContact(identifier: 0, state: 4, x: .nan, y: 0)], 13.02), nil)
    expectEqual(feed(&invalid, contacts(3), 13.03), nil)
    expectEqual(feed(&invalid, contacts(3, 0.09), 13.04), nil)
    expectEqual(feed(&invalid, [], 13.05), nil)
    expectEqual(feed(&invalid, contacts(3), 13.06), nil)
    expectEqual(feed(&invalid, contacts(3), 13.07), nil)
    expectEqual(feed(&invalid, contacts(3, 0.04), 13.08), nil)
    expectEqual(feed(&invalid, contacts(3, 0.09), 13.09), TrackpadSwipe(fingers: 3, direction: .right))
}

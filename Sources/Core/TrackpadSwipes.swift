import Foundation

/// One normalized MultitouchSupport contact. States 3 and 4 mean physical contact.
public struct TrackpadContact: Equatable {
    public let identifier: Int32
    public let state: Int32
    public let x: Double
    public let y: Double

    public init(identifier: Int32, state: Int32, x: Double, y: Double) {
        self.identifier = identifier
        self.state = state
        self.x = x
        self.y = y
    }
}

public struct TrackpadSwipe: Equatable {
    public let fingers: Int
    public let direction: SwipeDirection

    public init(fingers: Int, direction: SwipeDirection) {
        self.fingers = fingers
        self.direction = direction
    }
}

/// Pure frame recognizer. Coordinates are normalized to roughly 0...1.
/// Calibration: 0.08 normalized travel follows touchy's swipe scale;
/// 1.5:1 axis dominance rejects diagonals. Device/OS frame timing may vary.
public struct TrackpadSwipeState {
    private struct Point {
        let x: Double
        let y: Double
    }
    private struct Stroke {
        var lastTime: TimeInterval
        var ids: Set<Int32> = []
        var origins: [Int32: Point] = [:]
        var last: [Int32: Point] = [:]
        var fingers = 0
        var stableFrames = 0
        var moved = false
        var blocked = false
        var emitted = false
    }

    private var config: TrackpadConfig
    private var devices: [UInt64: Stroke] = [:]
    // Keep a device clock after lift so delayed frames cannot begin another stroke.
    private var lastTimes: [UInt64: TimeInterval] = [:]

    public init(config: TrackpadConfig = TrackpadConfig()) { self.config = config }

    public mutating func apply(_ config: TrackpadConfig) {
        guard self.config != config else { return }
        self.config = config
        // A reload cancels every in-flight stroke until that device fully lifts.
        for device in devices.keys { devices[device]?.blocked = true }
    }

    public mutating func removeDevice(_ device: UInt64) {
        devices.removeValue(forKey: device)
        lastTimes.removeValue(forKey: device)
    }

    public mutating func reset() {
        devices.removeAll()
        lastTimes.removeAll()
    }

    public mutating func handleFrame(device: UInt64, contacts: [TrackpadContact],
                                     timestamp: TimeInterval) -> TrackpadSwipe? {
        guard timestamp.isFinite, timestamp >= 0 else { return nil }
        guard timestamp >= (lastTimes[device] ?? -.infinity) else { return nil }
        lastTimes[device] = timestamp
        guard contacts.allSatisfy({ $0.x.isFinite && $0.y.isFinite &&
                                    (0...1).contains($0.x) && (0...1).contains($0.y) }) else {
            devices[device] = Stroke(lastTime: timestamp, blocked: true)
            return nil
        }
        let touching = contacts.filter { $0.state == 3 || $0.state == 4 }
        let ids = Set(touching.map(\.identifier))
        guard ids.count == touching.count else {
            devices[device] = Stroke(lastTime: timestamp, blocked: true)
            return nil
        }
        if ids.isEmpty {
            devices.removeValue(forKey: device)
            return nil
        }
        if ids.count <= 2 {
            if var stroke = devices[device] {
                stroke.blocked = true
                stroke.lastTime = timestamp
                devices[device] = stroke
            }
            return nil
        }
        if ids.count > 4 {
            devices[device] = Stroke(lastTime: timestamp, blocked: true)
            return nil
        }
        let points = Dictionary(uniqueKeysWithValues: touching.map { ($0.identifier, Point(x: $0.x, y: $0.y)) })
        var stroke = devices[device] ?? Stroke(lastTime: timestamp)
        if stroke.blocked || stroke.emitted {
            stroke.lastTime = timestamp
            devices[device] = stroke
            return nil
        }
        if stroke.ids != ids {
            if stroke.moved {
                stroke.blocked = true
            } else {
                stroke.ids = ids
                stroke.fingers = ids.count
                stroke.origins = points
                stroke.last = points
                stroke.stableFrames = 1
            }
            stroke.lastTime = timestamp
            devices[device] = stroke
            return nil
        }
        stroke.stableFrames += 1
        stroke.lastTime = timestamp
        defer { devices[device] = stroke }
        guard stroke.stableFrames >= 2, config.hasMappings(fingers: stroke.fingers) else { return nil }
        // Reject single-frame jumps (landing/identity discontinuity), while allowing
        // accumulated small steps to cross the swipe threshold.
        for id in ids {
            guard let previous = stroke.last[id], let current = points[id] else { return nil }
            let step = hypot(current.x - previous.x, current.y - previous.y)
            if step > 0.08 {
                stroke.blocked = true
                return nil
            }
        }
        stroke.last = points
        let displacements = ids.compactMap { id -> (Double, Double)? in
            guard let origin = stroke.origins[id], let current = points[id] else { return nil }
            return (current.x - origin.x, current.y - origin.y)
        }
        guard displacements.count == stroke.fingers else { return nil }
        let dx = displacements.reduce(0) { $0 + $1.0 } / Double(stroke.fingers)
        let dy = displacements.reduce(0) { $0 + $1.1 } / Double(stroke.fingers)
        if hypot(dx, dy) > 0.008 { stroke.moved = true }
        let major = max(abs(dx), abs(dy))
        let minor = min(abs(dx), abs(dy))
        guard major >= 0.08, major >= minor * 1.5 else { return nil }
        let direction: SwipeDirection = abs(dx) > abs(dy) ? (dx > 0 ? .right : .left) : (dy > 0 ? .up : .down)
        let aligned = displacements.allSatisfy { x, y in
            let travel: Double
            switch direction {
            case .up: travel = y
            case .down: travel = -y
            case .left: travel = -x
            case .right: travel = x
            }
            return travel >= major * 0.5
        }
        guard aligned, config.action(fingers: stroke.fingers, direction: direction) != nil else { return nil }
        stroke.emitted = true
        return TrackpadSwipe(fingers: stroke.fingers, direction: direction)
    }

}

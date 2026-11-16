import Foundation
import CoreGraphics
import HyperMugCore

/// CGEventTap glue: installs the session tap, turns each CGEvent into a `TapEvent`, applies the decision.
/// All decisions live in Core (`TapState`/`Engine`); the host must outlive the tap (the callback holds it unretained).
final class EventTapHost {
    /// Set by the composition root: `engine.handleTapEvent`. Without a handler every event passes.
    var handler: ((TapEvent) -> TapDecision)?

    private let log: LogSink
    private var port: CFMachPort?
    private var source: CFRunLoopSource?

    init(log: @escaping LogSink) {
        self.log = log
    }

    /// Replace semantics: creates the new tap before dropping the old one, so no event goes unobserved in between.
    /// Returns false when the tap could not be created; no tap is installed then. Main thread only, which is also
    /// where the callback runs.
    func install(mask: CGEventMask) -> Bool {
        let old = (port: port, source: source)
        port = nil
        source = nil
        let created = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        if let tap = created {
            let tapSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), tapSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            port = tap
            source = tapSource
            if !CGEvent.tapIsEnabled(tap: tap) { log(.error, "event tap created but not enabled") }
        } else {
            log(.error, "CGEvent.tapCreate returned nil")
        }
        if let oldPort = old.port { destroy(port: oldPort, source: old.source) }
        return created != nil
    }

    func remove() {
        if let port { destroy(port: port, source: source) }
        port = nil
        source = nil
    }

    private func destroy(port: CFMachPort, source: CFRunLoopSource?) {
        CGEvent.tapEnable(tap: port, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(port)
    }

    fileprivate func dispatch(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard let handler else { return Unmanaged.passUnretained(event) }
        let decision: TapDecision
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // These notifications carry no usable event; don't read fields from it.
            decision = handler(TapEvent(type: type))
        } else {
            decision = handler(TapEvent(
                type: type,
                userData: event.getIntegerValueField(.eventSourceUserData),
                keyCode: event.getIntegerValueField(.keyboardEventKeycode),
                flags: event.flags,
                button: event.getIntegerValueField(.mouseEventButtonNumber),
                scrollPhase: event.getIntegerValueField(.scrollWheelEventScrollPhase),
                momentumPhase: event.getIntegerValueField(.scrollWheelEventMomentumPhase),
                vertical: ScrollAxis(
                    line: event.getIntegerValueField(.scrollWheelEventDeltaAxis1),
                    fixed: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1),
                    point: event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)),
                horizontal: ScrollAxis(
                    line: event.getIntegerValueField(.scrollWheelEventDeltaAxis2),
                    fixed: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2),
                    point: event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2))
            ))
        }

        if decision.reenableTap, let port { CGEvent.tapEnable(tap: port, enable: true) }
        if let flags = decision.flags { event.flags = flags }
        // DeltaAxis goes first: setting it makes macOS recompute the other two fields, which are then overwritten.
        if let axis = decision.vertical {
            event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: axis.line)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: axis.fixed)
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: axis.point)
        }
        if let axis = decision.horizontal {
            event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: axis.line)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: axis.fixed)
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: axis.point)
        }
        return decision.pass ? Unmanaged.passUnretained(event) : nil
    }
}

private func eventTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    return Unmanaged<EventTapHost>.fromOpaque(refcon).takeUnretainedValue().dispatch(type: type, event: event)
}

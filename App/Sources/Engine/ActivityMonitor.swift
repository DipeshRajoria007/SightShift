import AppKit
import SightShiftCore

/// Keeps track of when you last typed or used the mouse, and reports clicks for learning.
@MainActor
final class ActivityMonitor {
    /// Marks events SightShift posts itself, so they don't count as your activity.
    nonisolated static let syntheticEventTag: Int64 = 0x5347_5348

    /// Called with the click position (global top-left coordinates) and time (system uptime).
    var onClick: ((CGPoint, Double) -> Void)?

    private var lastKeyDown = -Double.infinity
    private var recentKeys: [Double] = []
    private var lastPointer = -Double.infinity
    private var lastSyntheticClick = -Double.infinity
    private var monitors: [Any] = []

    func start() {
        guard monitors.isEmpty else { return }
        if let keys = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            self?.noteKey(at: event.timestamp)
        }) {
            monitors.append(keys)
        }
        let pointerEvents: NSEvent.EventTypeMask = [
            .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel,
            .leftMouseDown, .rightMouseDown, .otherMouseDown, .magnify, .swipe, .rotate,
        ]
        if let pointer = NSEvent.addGlobalMonitorForEvents(matching: pointerEvents, handler: { [weak self] event in
            self?.handlePointer(event)
        }) {
            monitors.append(pointer)
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
    }

    private func noteKey(at time: Double) {
        lastKeyDown = time
        recentKeys.append(time)
        if let first = recentKeys.first, time - first > 5 {
            recentKeys.removeAll { time - $0 > 5 }
        }
    }

    private func handlePointer(_ event: NSEvent) {
        if event.cgEvent?.getIntegerValueField(.eventSourceUserData) == Self.syntheticEventTag { return }
        lastPointer = event.timestamp
        if event.type == .leftMouseDown {
            onClick?(Displays.globalPoint(fromCocoa: NSEvent.mouseLocation), event.timestamp)
        }
    }

    /// SightShift clicked a pane itself at `time`; that isn't you using the mouse.
    func noteSyntheticClick(at time: Double) {
        lastSyntheticClick = time
    }

    /// Latest activity, also consulting the window server's idle counters in case an event
    /// monitor missed something.
    func times(now: Double) -> ActivityTimes {
        let state = CGEventSourceStateID.combinedSessionState
        let keyIdle = CGEventSource.secondsSinceLastEventType(state, eventType: .keyDown)
        let pointerIdle = [CGEventType.mouseMoved, .leftMouseDown, .rightMouseDown, .leftMouseDragged, .scrollWheel]
            .map { CGEventSource.secondsSinceLastEventType(state, eventType: $0) }
            .min() ?? .infinity
        var pointer = lastPointer
        let counted = now - pointerIdle
        // The idle counters can't tell SightShift's own clicks from yours.
        if counted < lastSyntheticClick - 0.05 || counted > lastSyntheticClick + 0.4 {
            pointer = max(pointer, counted)
        }
        return ActivityTimes(lastKeyDown: max(lastKeyDown, now - keyIdle), lastPointer: pointer, recentKeys: recentKeys)
    }
}

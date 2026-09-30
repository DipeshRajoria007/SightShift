import Foundation

/// A change of gaze target that has been held long enough to count.
public struct GazeTransition<ID: Hashable & Sendable>: Equatable, Sendable {
    public let target: ID
    /// When the gaze first landed on `target`.
    public let arrivedAt: Double
    /// When it had stayed there for the full dwell time.
    public let settledAt: Double
}

/// Turns a stream of per-frame guesses into settled targets: a new target only counts once it
/// has been seen continuously for the dwell time, so quick glances are ignored.
public struct DwellTracker<ID: Hashable & Sendable>: Sendable {
    /// The settled target, if any.
    public private(set) var stable: ID?
    /// A different target that is currently being dwelled on.
    public private(set) var pending: ID?
    public private(set) var pendingSince = 0.0
    private var pendingLastSeen = 0.0

    /// How long a run of "no information" frames (a blink, a lost face) may interrupt a dwell
    /// before it starts over.
    public var gapTolerance: Double

    public init(gapTolerance: Double = 0.25) {
        self.gapTolerance = gapTolerance
    }

    /// Feeds the guess for one frame; `nil` means this frame carries no information.
    /// Returns a transition when the settled target changes.
    public mutating func update(_ candidate: ID?, now: Double, dwell: Double) -> GazeTransition<ID>? {
        guard let candidate else {
            if pending != nil, now - pendingLastSeen > gapTolerance { pending = nil }
            return nil
        }
        if candidate == stable {
            pending = nil
            return nil
        }
        if candidate != pending || now - pendingLastSeen > gapTolerance {
            pending = candidate
            pendingSince = now
        }
        pendingLastSeen = now
        guard now - pendingSince >= dwell - 1e-9 else { return nil }
        stable = candidate
        pending = nil
        return GazeTransition(target: candidate, arrivedAt: pendingSince, settledAt: now)
    }

    public mutating func reset(to target: ID? = nil) {
        stable = target
        pending = nil
    }
}

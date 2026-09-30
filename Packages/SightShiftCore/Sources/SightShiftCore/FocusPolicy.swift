import Foundation

/// Timestamps (seconds on a monotonic clock) of the user's latest keyboard and pointer activity.
public struct ActivityTimes: Equatable, Sendable {
    public var lastKeyDown: Double
    public var lastPointer: Double
    /// Times of the last few seconds of keystrokes, oldest first, when they're known.
    public var recentKeys: [Double]

    public init(lastKeyDown: Double = -.infinity, lastPointer: Double = -.infinity, recentKeys: [Double] = []) {
        self.lastKeyDown = lastKeyDown
        self.lastPointer = lastPointer
        self.recentKeys = recentKeys
    }
}

public struct GuardSettings: Equatable, Sendable {
    /// Hold focus while you're typing.
    public var waitWhileTyping: Bool
    /// How long typing must pause before focus may move.
    public var typingPause: Double
    /// How long the mouse or trackpad must rest before focus may move.
    public var pointerPause: Double

    public init(waitWhileTyping: Bool = true, typingPause: Double = 2.0, pointerPause: Double = 1.5) {
        self.waitWhileTyping = waitWhileTyping
        self.typingPause = typingPause
        self.pointerPause = pointerPause
    }
}

public enum FocusHold: Equatable, Sendable {
    case typing(remaining: Double)
    case pointer(remaining: Double)
}

public enum MoveVerdict: Equatable, Sendable {
    case perform
    case wait(FocusHold)
    /// Drop the move: typing carried straight on through the turn, which means you're reading
    /// over there while typing here.
    case cancel
}

/// A settled gaze change that hasn't been acted on yet.
public struct PendingMove<ID: Hashable & Sendable>: Equatable, Sendable {
    /// Keystrokes closer together than this belong to one burst of typing.
    public static var burstGap: Double { 0.8 }

    public let transition: GazeTransition<ID>
    /// The last keystroke known when the move settled; only used when there's no keystroke history.
    public let keyBeforeSettle: Double
    /// The first keystroke seen after the move settled, likewise.
    public private(set) var keyAfterSettle: Double?

    public init(_ transition: GazeTransition<ID>, lastKeyDown: Double) {
        self.transition = transition
        self.keyBeforeSettle = lastKeyDown
    }

    public var target: ID { transition.target }

    /// What to do with the move now.
    ///
    /// Typing that runs straight through the turn (a keystroke shortly before the gaze settled and
    /// another shortly after) cancels the move. Typing that stopped before the turn only delays it
    /// until typing has paused for `typingPause`, like any other typing.
    public mutating func verdict(now: Double, activity: ActivityTimes, settings: GuardSettings) -> MoveVerdict {
        if keyAfterSettle == nil, activity.lastKeyDown > transition.settledAt {
            keyAfterSettle = activity.lastKeyDown
        }
        if settings.waitWhileTyping, typedThroughTurn(activity) {
            return .cancel
        }
        if let hold = FocusPolicy.hold(now: now, activity: activity, settings: settings) {
            return .wait(hold)
        }
        return .perform
    }

    private func typedThroughTurn(_ activity: ActivityTimes) -> Bool {
        let settled = transition.settledAt
        if !activity.recentKeys.isEmpty {
            guard let before = activity.recentKeys.last(where: { $0 <= settled }),
                  let after = activity.recentKeys.first(where: { $0 > settled }) else { return false }
            return after - before < Self.burstGap
        }
        guard let after = keyAfterSettle else { return false }
        return after - keyBeforeSettle < Self.burstGap
    }
}

public enum FocusPolicy {
    public static func hold(now: Double, activity: ActivityTimes, settings: GuardSettings) -> FocusHold? {
        let pointerRemaining = activity.lastPointer + settings.pointerPause - now
        if pointerRemaining > 0 { return .pointer(remaining: pointerRemaining) }
        if settings.waitWhileTyping {
            let typingRemaining = activity.lastKeyDown + settings.typingPause - now
            if typingRemaining > 0 { return .typing(remaining: typingRemaining) }
        }
        return nil
    }
}

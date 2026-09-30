import CoreGraphics
import XCTest
@testable import SightShiftCore

final class DwellTrackerTests: XCTestCase {
    private func settled(on target: String) -> DwellTracker<String> {
        var tracker = DwellTracker<String>(gapTolerance: 0.25)
        _ = tracker.update(target, now: 0, dwell: 0.3)
        _ = tracker.update(target, now: 0.2, dwell: 0.3)
        _ = tracker.update(target, now: 0.3, dwell: 0.3)
        return tracker
    }

    func testTheFirstTargetAlsoNeedsTheDwell() {
        var tracker = DwellTracker<String>()
        XCTAssertNil(tracker.update("A", now: 0, dwell: 0.3))
        XCTAssertNil(tracker.stable)
        XCTAssertEqual(tracker.update("A", now: 0.2, dwell: 0.3), nil)
        XCTAssertEqual(tracker.update("A", now: 0.3, dwell: 0.3)?.target, "A")
    }

    func testQuickGlancesAreIgnored() {
        var tracker = settled(on: "A")
        XCTAssertEqual(tracker.stable, "A")

        XCTAssertNil(tracker.update("B", now: 1.0, dwell: 0.3))
        XCTAssertNil(tracker.update("B", now: 1.2, dwell: 0.3))
        XCTAssertNil(tracker.update("A", now: 1.25, dwell: 0.3))
        XCTAssertEqual(tracker.stable, "A")
        XCTAssertNil(tracker.pending)
    }

    func testSettlingSwitchesAndReportsArrival() {
        var tracker = settled(on: "A")
        XCTAssertNil(tracker.update("B", now: 1.0, dwell: 0.3))
        XCTAssertNil(tracker.update("B", now: 1.2, dwell: 0.3))
        let transition = tracker.update("B", now: 1.31, dwell: 0.3)
        XCTAssertEqual(transition, GazeTransition(target: "B", arrivedAt: 1.0, settledAt: 1.31))
        XCTAssertEqual(tracker.stable, "B")
    }

    func testShortDropoutsDoNotRestartTheDwell() {
        var tracker = settled(on: "A")
        _ = tracker.update("B", now: 1.0, dwell: 0.3)
        XCTAssertNil(tracker.update(nil, now: 1.1, dwell: 0.3))
        XCTAssertNil(tracker.update("B", now: 1.2, dwell: 0.3))
        XCTAssertEqual(tracker.update("B", now: 1.3, dwell: 0.3)?.arrivedAt, 1.0)
    }

    func testLongDropoutsRestartTheDwell() {
        var tracker = settled(on: "A")
        _ = tracker.update("B", now: 1.0, dwell: 0.3)
        _ = tracker.update(nil, now: 1.5, dwell: 0.3)
        XCTAssertNil(tracker.update("B", now: 1.6, dwell: 0.3))
        XCTAssertNil(tracker.update("B", now: 1.75, dwell: 0.3))
        XCTAssertEqual(tracker.update("B", now: 1.9, dwell: 0.3)?.arrivedAt, 1.6)
    }
}

final class FocusPolicyTests: XCTestCase {
    private let settings = GuardSettings(waitWhileTyping: true, typingPause: 2.0, pointerPause: 1.5)
    private let turn = GazeTransition(target: "B", arrivedAt: 10, settledAt: 10.3)

    func testWaitsForThePointerToRest() {
        var move = PendingMove(turn, lastKeyDown: 0)
        let activity = ActivityTimes(lastKeyDown: 0, lastPointer: 9.5)
        guard case .wait(.pointer(let remaining)) = move.verdict(now: 10.3, activity: activity, settings: settings) else {
            return XCTFail("expected a pointer hold")
        }
        XCTAssertEqual(remaining, 0.7, accuracy: 1e-9)
        XCTAssertEqual(move.verdict(now: 11.1, activity: activity, settings: settings), .perform)
    }

    func testWaitsForTypingToPause() {
        // Typing stopped just before the turn: the move waits out the typing pause, then happens.
        var move = PendingMove(turn, lastKeyDown: 9.8)
        let activity = ActivityTimes(lastKeyDown: 9.8, lastPointer: 0)
        guard case .wait(.typing) = move.verdict(now: 10.3, activity: activity, settings: settings) else {
            return XCTFail("expected a typing hold")
        }
        XCTAssertEqual(move.verdict(now: 11.9, activity: activity, settings: settings), .perform)
    }

    func testTypingStraightThroughTheTurnCancelsTheMove() {
        // Reading the other screen while typing on this one.
        var move = PendingMove(turn, lastKeyDown: 10.25)
        XCTAssertNotEqual(move.verdict(now: 10.3, activity: ActivityTimes(lastKeyDown: 10.25, lastPointer: 0), settings: settings), .cancel)
        XCTAssertEqual(move.verdict(now: 10.5, activity: ActivityTimes(lastKeyDown: 10.45, lastPointer: 0), settings: settings), .cancel)
    }

    func testANewBurstAfterAGapOnlyDelaysTheMove() {
        // Finished typing, turned, paused, then started typing again: not reading-while-typing.
        var move = PendingMove(turn, lastKeyDown: 9.0)
        XCTAssertNotEqual(move.verdict(now: 10.3, activity: ActivityTimes(lastKeyDown: 9.0, lastPointer: 0), settings: settings), .cancel)
        guard case .wait(.typing) = move.verdict(now: 11.0, activity: ActivityTimes(lastKeyDown: 10.9, lastPointer: 0), settings: settings) else {
            return XCTFail("expected a typing hold")
        }
        XCTAssertEqual(move.verdict(now: 13.0, activity: ActivityTimes(lastKeyDown: 10.9, lastPointer: 0), settings: settings), .perform)
    }

    func testKeystrokeHistoryDecidesPrecisely() {
        // No typing before the turn: a key right after it settles is a fresh start, not a cancel.
        var fresh = PendingMove(turn, lastKeyDown: 10.33)
        let afterOnly = ActivityTimes(lastKeyDown: 10.33, lastPointer: 0, recentKeys: [10.33])
        XCTAssertNotEqual(fresh.verdict(now: 10.4, activity: afterOnly, settings: settings), .cancel)

        // Typing on both sides of the moment it settled: reading there while typing here.
        var through = PendingMove(turn, lastKeyDown: 10.2)
        let both = ActivityTimes(lastKeyDown: 10.5, lastPointer: 0, recentKeys: [9.9, 10.1, 10.2, 10.35, 10.5])
        XCTAssertEqual(through.verdict(now: 10.6, activity: both, settings: settings), .cancel)
    }

    func testTypingGuardCanBeTurnedOff() {
        let relaxed = GuardSettings(waitWhileTyping: false, typingPause: 2.0, pointerPause: 1.5)
        var move = PendingMove(turn, lastKeyDown: 10.2)
        XCTAssertEqual(move.verdict(now: 10.4, activity: ActivityTimes(lastKeyDown: 10.35, lastPointer: 0), settings: relaxed), .perform)
    }
}

final class TargetSelectorTests: XCTestCase {
    private let left = FocusTarget(id: "left", frame: CGRect(x: 0, y: 0, width: 500, height: 800))
    private let right = FocusTarget(id: "right", frame: CGRect(x: 500, y: 0, width: 500, height: 800))

    func testKeepsTheCurrentTargetAnywhereInsideIt() {
        XCTAssertEqual(TargetSelector.select(point: CGPoint(x: 495, y: 400), targets: [left, right], current: "left"), "left")
    }

    func testNewTargetsMustBeEnteredComfortably() {
        XCTAssertNil(TargetSelector.select(point: CGPoint(x: 520, y: 400), targets: [left, right], current: "left"))
        XCTAssertEqual(TargetSelector.select(point: CGPoint(x: 700, y: 400), targets: [left, right], current: "left"), "right")
    }

    func testFrontTargetsWin() {
        let floating = FocusTarget(id: "floating", frame: CGRect(x: 100, y: 100, width: 600, height: 400))
        XCTAssertEqual(TargetSelector.select(point: CGPoint(x: 400, y: 300), targets: [floating, left, right], current: "left"), "floating")
    }

    func testWindowsThatCantTakeFocusStillBlockTheOnesBehind() {
        let palette = FocusTarget(id: "palette", frame: CGRect(x: 600, y: 100, width: 300, height: 300), isSelectable: false)
        XCTAssertNil(TargetSelector.select(point: CGPoint(x: 700, y: 200), targets: [palette, left, right], current: "left"))
    }

    func testOutsideEverythingIsUnknown() {
        XCTAssertNil(TargetSelector.select(point: CGPoint(x: 1500, y: 400), targets: [left, right], current: "left"))
    }
}

final class OneEuroFilterTests: XCTestCase {
    func testSmoothsNoiseButFollowsRealMoves() {
        var random = SeededRandom(seed: 7)
        var filter = OneEuroFilter(minCutoff: 1.0, beta: 0.5)
        var rawVariance = 0.0
        var filteredVariance = 0.0
        for i in 0..<300 {
            let noisy = random.gaussian(0.1)
            let smoothed = filter.filter(noisy, time: Double(i) / 15)
            if i > 30 {
                rawVariance += noisy * noisy
                filteredVariance += smoothed * smoothed
            }
        }
        XCTAssertLessThan(filteredVariance, rawVariance / 3)

        // A step change is followed within a fraction of a second.
        var value = 0.0
        for i in 300..<310 { value = filter.filter(5, time: Double(i) / 15) }
        XCTAssertGreaterThan(value, 4.5)
    }

    func testRestartsAfterLongGaps() {
        var filter = OneEuroFilter(minCutoff: 1.0, beta: 0, resetAfter: 0.5)
        _ = filter.filter(0, time: 0)
        XCTAssertEqual(filter.filter(10, time: 2), 10)
    }
}

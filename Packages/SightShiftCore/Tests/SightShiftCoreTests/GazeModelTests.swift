import XCTest
@testable import SightShiftCore

final class GazeModelTests: XCTestCase {
    private func trainedModel(_ user: inout SyntheticUser) throws -> GazeModel {
        let profile = user.calibrate()
        return try XCTUnwrap(GazeModel.train(profile: profile, screenKeys: user.screens.map(\.key)))
    }

    func testTellsThreeScreensApart() throws {
        var user = SyntheticUser.threeScreens()
        let model = try trainedModel(&user)

        for screen in user.screens {
            var correct = 0
            let trials = 200
            for _ in 0..<trials {
                let features = user.features(screen: screen, at: user.randomPoint())
                if model.estimate(features, current: nil, threshold: 0.5, hysteresis: 0.08).nearest == screen.key { correct += 1 }
            }
            XCTAssertGreaterThan(Double(correct) / Double(trials), 0.97, "screen \(screen.key)")
        }
        let accuracy = try XCTUnwrap(model.report.overallAccuracy)
        XCTAssertGreaterThan(accuracy, 0.95)
    }

    func testEstimatesWhereOnTheScreen() throws {
        var user = SyntheticUser.threeScreens()
        let model = try trainedModel(&user)

        for screen in user.screens {
            var squaredError = 0.0
            let trials = 200
            for _ in 0..<trials {
                let point = user.randomPoint()
                let estimate = try XCTUnwrap(model.point(on: screen.key, features: user.features(screen: screen, at: point)))
                squaredError += pow(estimate.u - point.u, 2) + pow(estimate.v - point.v, 2)
            }
            let rms = (squaredError / Double(trials)).squareRoot()
            XCTAssertLessThan(rms, 0.12, "screen \(screen.key)")
        }
    }

    func testIgnoresPosesAwayFromEveryScreen() throws {
        var user = SyntheticUser.threeScreens()
        let model = try trainedModel(&user)

        // A phone on the desk, the ceiling, and a window far to the right.
        for (yaw, pitch) in [(0.0, -55.0), (0.0, 60.0), (70.0, 0.0)] {
            var ignored = 0
            for _ in 0..<50 {
                let estimate = model.estimate(user.features(yaw: yaw, pitch: pitch), current: "above", threshold: 0.5, hysteresis: 0.08)
                if estimate.screen == nil || estimate.screen == "above" { ignored += 1 }
            }
            XCTAssertGreaterThanOrEqual(ignored, 48, "pose yaw \(yaw) pitch \(pitch)")
        }
    }

    func testGoingBackNeedsABiggerTurn() throws {
        var user = SyntheticUser.threeScreens()
        user.noise = 0
        let model = try trainedModel(&user)
        let laptop = user.screens[0]
        let above = user.screens[1]

        func sweep(from start: SimScreen, to end: SimScreen, current initial: String) -> Double? {
            var current = initial
            for step in 0...100 {
                let t = Double(step) / 100
                let pitch = start.pitch + (end.pitch - start.pitch) * t
                let estimate = model.estimate(user.features(yaw: 0, pitch: pitch), current: current, threshold: 0.5, hysteresis: 0.08)
                if let screen = estimate.screen, screen != current {
                    current = screen
                    return t
                }
            }
            return nil
        }

        let up = try XCTUnwrap(sweep(from: laptop, to: above, current: "laptop"))
        let down = try XCTUnwrap(sweep(from: above, to: laptop, current: "above"))
        // Measured along the same line, switching up happens further up than switching back down.
        XCTAssertGreaterThan(up, 1 - down + 0.05)
    }

    func testLearningFromClicksAdaptsToANewSeat() throws {
        var user = SyntheticUser.threeScreens()
        var profile = user.calibrate()
        let keys = user.screens.map(\.key)

        // The user moves to the side: the face shifts in the frame and every screen appears at
        // a different angle.
        user.seatShiftX = 0.12
        user.seatYawOffset = 9

        func accuracy(_ model: GazeModel) -> Double {
            var correct = 0
            var total = 0
            for screen in user.screens {
                for _ in 0..<150 {
                    let features = user.features(screen: screen, at: user.randomPoint())
                    if model.estimate(features, current: nil, threshold: 0.5, hysteresis: 0.08).nearest == screen.key { correct += 1 }
                    total += 1
                }
            }
            return Double(correct) / Double(total)
        }

        let before = try XCTUnwrap(GazeModel.train(profile: profile, screenKeys: keys))
        let accuracyBefore = accuracy(before)

        for screen in user.screens {
            for _ in 0..<30 {
                let point = user.randomPoint()
                profile.addLearned(GazeSample(features: user.features(screen: screen, at: point), u: point.u, v: point.v, point: GazeSample.learned, time: 0), screen: screen.key)
            }
        }
        let after = try XCTUnwrap(GazeModel.train(profile: profile, screenKeys: keys))
        let accuracyAfter = accuracy(after)

        XCTAssertGreaterThan(accuracyAfter, 0.95)
        XCTAssertGreaterThanOrEqual(accuracyAfter, accuracyBefore)
    }

    func testSingleScreenStillGatesOffScreenPoses() throws {
        var user = SyntheticUser(screens: [SimScreen(key: "only", yaw: 0, pitch: 0, width: 45, height: 25)])
        let model = try trainedModel(&user)

        let onScreen = model.estimate(user.features(yaw: 5, pitch: 3), current: nil, threshold: 0.5, hysteresis: 0.08)
        XCTAssertEqual(onScreen.screen, "only")
        let phone = model.estimate(user.features(yaw: 0, pitch: -50), current: "only", threshold: 0.5, hysteresis: 0.08)
        XCTAssertNil(phone.screen)
    }

    func testUncalibratedScreensAreLeftOut() throws {
        var user = SyntheticUser.threeScreens()
        let profile = user.calibrate()
        let model = try XCTUnwrap(GazeModel.train(profile: profile, screenKeys: ["laptop", "new-monitor", "left"]))
        XCTAssertEqual(model.screenKeys, ["laptop", "left"])
    }
}

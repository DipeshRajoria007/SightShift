import Foundation
@testable import SightShiftCore

/// Deterministic random numbers so the simulations are reproducible.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func uniform() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    mutating func uniform(_ range: ClosedRange<Double>) -> Double {
        range.lowerBound + uniform() * (range.upperBound - range.lowerBound)
    }

    mutating func gaussian(_ sigma: Double) -> Double {
        let u1 = max(uniform(), 1e-12)
        let u2 = uniform()
        return sigma * (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }
}

/// A screen described by the angles at which the user sees it.
struct SimScreen {
    var key: String
    /// Direction of the screen centre, in degrees (positive yaw = user's right, positive pitch = up).
    var yaw: Double
    var pitch: Double
    /// Angular size in degrees.
    var width: Double
    var height: Double
}

/// A crude but useful model of a person looking at screens: the head covers most of each gaze
/// shift and the eyes cover the rest, and every measurement is noisy.
struct SyntheticUser {
    var screens: [SimScreen]
    /// Share of a gaze shift made by turning the head.
    var headShare = 0.7
    /// Where the user sits: sideways shift of the face in the camera frame and the angular
    /// change that shift causes when looking at the screens.
    var seatShiftX = 0.0
    var seatYawOffset = 0.0
    var noise = 1.0
    var random = SeededRandom(seed: 42)

    init(screens: [SimScreen]) { self.screens = screens }

    static func threeScreens() -> SyntheticUser {
        SyntheticUser(screens: [
            SimScreen(key: "laptop", yaw: 0, pitch: -18, width: 30, height: 19),
            SimScreen(key: "above", yaw: 0, pitch: 12, width: 45, height: 25),
            SimScreen(key: "left", yaw: -50, pitch: 3, width: 45, height: 25),
        ])
    }

    func gazeAngles(screen: SimScreen, at point: ScreenPoint) -> (yaw: Double, pitch: Double) {
        (screen.yaw + (point.u - 0.5) * screen.width, screen.pitch - (point.v - 0.5) * screen.height)
    }

    mutating func features(yaw gazeYawDegrees: Double, pitch gazePitchDegrees: Double) -> [Double] {
        let gazeYaw = (gazeYawDegrees + seatYawOffset) * .pi / 180
        let gazePitch = gazePitchDegrees * .pi / 180
        let headYaw = headShare * gazeYaw + random.gaussian(0.015 * noise)
        let headPitch = headShare * gazePitch + random.gaussian(0.02 * noise)
        let eyeYaw = gazeYaw - headYaw
        let eyePitch = gazePitch - headPitch

        var f = [Double](repeating: 0, count: Feature.count)
        f[Feature.yaw.rawValue] = headYaw + random.gaussian(0.02 * noise)
        f[Feature.pitch.rawValue] = headPitch + random.gaussian(0.03 * noise)
        f[Feature.noseX.rawValue] = 0.5 * sin(headYaw) + random.gaussian(0.01 * noise)
        f[Feature.noseY.rawValue] = -0.7 + 0.5 * sin(headPitch) + random.gaussian(0.01 * noise)
        f[Feature.contourAsymmetry.rawValue] = 1.1 * sin(headYaw) + random.gaussian(0.02 * noise)
        f[Feature.eyeX.rawValue] = 0.6 * eyeYaw + random.gaussian(0.03 * noise)
        f[Feature.eyeY.rawValue] = 0.4 * eyePitch + random.gaussian(0.04 * noise)
        f[Feature.faceX.rawValue] = 0.5 + seatShiftX + 0.08 * sin(headYaw) + random.gaussian(0.003 * noise)
        f[Feature.faceY.rawValue] = 0.55 + 0.05 * sin(headPitch) + random.gaussian(0.003 * noise)
        f[Feature.faceScale.rawValue] = 0.075 * (1 - 0.1 * abs(sin(headYaw))) + random.gaussian(0.0005 * noise)
        return f
    }

    mutating func features(screen: SimScreen, at point: ScreenPoint) -> [Double] {
        let angles = gazeAngles(screen: screen, at: point)
        return features(yaw: angles.yaw, pitch: angles.pitch)
    }

    static let calibrationGrid: [ScreenPoint] = {
        let stops = [0.08, 0.5, 0.92]
        return stops.flatMap { v in stops.map { u in ScreenPoint(u: u, v: v) } }
    }()

    /// Simulates the calibration routine: a dozen frames per dot on every screen.
    mutating func calibrate(framesPerDot: Int = 14) -> CalibrationProfile {
        var profile = CalibrationProfile()
        for screen in screens {
            var samples: [GazeSample] = []
            for (index, point) in Self.calibrationGrid.enumerated() {
                for _ in 0..<framesPerDot {
                    samples.append(GazeSample(features: features(screen: screen, at: point), u: point.u, v: point.v, point: index, time: 0))
                }
            }
            profile.setCalibration(ScreenCalibration(screenKey: screen.key, screenName: screen.key, calibratedAt: Date(), samples: samples))
        }
        return profile
    }

    mutating func randomPoint() -> ScreenPoint {
        ScreenPoint(u: random.uniform(0.05...0.95), v: random.uniform(0.05...0.95))
    }
}

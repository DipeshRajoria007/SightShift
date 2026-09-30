import CoreGraphics
import XCTest
@testable import SightShiftCore

final class MatrixTests: XCTestCase {
    func testSolvesSymmetricPositiveDefiniteSystems() throws {
        let a = Matrix([[4, 2, 0.6], [2, 5, 1], [0.6, 1, 3]])
        let expected = [1.0, -2.0, 0.5]
        let b = a * expected
        let x = try XCTUnwrap(a.solveSymmetricPositiveDefinite(b))
        for (lhs, rhs) in zip(x, expected) { XCTAssertEqual(lhs, rhs, accuracy: 1e-10) }
    }

    func testRejectsIndefiniteMatrices() {
        XCTAssertNil(Matrix([[1, 2], [2, 1]]).cholesky())
    }

    func testInvertsLowerTriangularMatrices() throws {
        let l = try XCTUnwrap(Matrix([[4, 2], [2, 3]]).cholesky())
        let product = l * l.lowerTriangularInverse()
        XCTAssertEqual(product[0, 0], 1, accuracy: 1e-12)
        XCTAssertEqual(product[1, 1], 1, accuracy: 1e-12)
        XCTAssertEqual(product[1, 0], 0, accuracy: 1e-12)
    }

    func testSegmentDistance() {
        XCTAssertEqual(Vec.distanceToSegment([1, 1], [0, 0], [2, 0]), 1, accuracy: 1e-12)
        XCTAssertEqual(Vec.distanceToSegment([3, 0], [0, 0], [2, 0]), 1, accuracy: 1e-12)
    }
}

final class FaceGeometryTests: XCTestCase {
    /// A roughly human, perfectly frontal face in a 1280×720 frame.
    private func frontalFace(noseShift: CGFloat = 0, scale: CGFloat = 1, offset: CGPoint = .zero) -> FaceLandmarks {
        func eye(_ cx: CGFloat) -> [CGPoint] {
            [(-16, 0), (-8, 6), (8, 6), (16, 0), (8, -5), (-8, -5)].map { CGPoint(x: cx + $0.0, y: 400 + $0.1) }
        }
        let nose = [(-12, -40), (0, -30), (12, -40), (0, -55), (-6, -58), (6, -58)].map {
            CGPoint(x: 640 + $0.0 + noseShift, y: 400 + $0.1)
        }
        let contour = stride(from: -1.0, through: 1.0, by: 0.125).map { t -> CGPoint in
            CGPoint(x: 640 + 110 * t, y: 400 - 120 * (1 - t * t) + 10)
        }
        func transform(_ p: CGPoint) -> CGPoint {
            CGPoint(x: (p.x - 640) * scale + 640 + offset.x, y: (p.y - 400) * scale + 400 + offset.y)
        }
        return FaceLandmarks(
            leftEye: eye(595).map(transform),
            rightEye: eye(685).map(transform),
            leftPupil: transform(CGPoint(x: 595, y: 400)),
            rightPupil: transform(CGPoint(x: 685, y: 400)),
            nose: nose.map(transform),
            faceContour: contour.map(transform)
        )
    }

    private let frame = CGSize(width: 1280, height: 720)
    private let noPose = HeadPose(yaw: nil, pitch: nil, roll: nil)

    func testFrontalFaceIsCentred() throws {
        let m = try XCTUnwrap(FaceGeometry.measure(landmarks: frontalFace(), pose: noPose, imageSize: frame))
        XCTAssertEqual(m[.noseX], 0, accuracy: 1e-9)
        XCTAssertEqual(m[.contourAsymmetry], 0, accuracy: 1e-9)
        XCTAssertEqual(m[.eyeX], 0, accuracy: 1e-9)
        XCTAssertEqual(m[.faceScale], 90.0 / 1280, accuracy: 1e-9)
        XCTAssertFalse(m.isBlinking)
    }

    func testNoseOffsetFollowsTheNose() throws {
        let right = try XCTUnwrap(FaceGeometry.measure(landmarks: frontalFace(noseShift: 12), pose: noPose, imageSize: frame))
        let left = try XCTUnwrap(FaceGeometry.measure(landmarks: frontalFace(noseShift: -12), pose: noPose, imageSize: frame))
        XCTAssertGreaterThan(right[.noseX], 0.1)
        XCTAssertEqual(right[.noseX], -left[.noseX], accuracy: 1e-9)
    }

    func testDistanceAndPositionDoNotLeakIntoOrientation() throws {
        let base = try XCTUnwrap(FaceGeometry.measure(landmarks: frontalFace(noseShift: 8), pose: noPose, imageSize: frame))
        let moved = try XCTUnwrap(FaceGeometry.measure(landmarks: frontalFace(noseShift: 8, scale: 1.4, offset: CGPoint(x: 120, y: -40)), pose: noPose, imageSize: frame))
        for feature in [Feature.noseX, .noseY, .contourAsymmetry, .eyeX, .eyeY] {
            XCTAssertEqual(base[feature], moved[feature], accuracy: 1e-9, "\(feature)")
        }
        XCTAssertGreaterThan(moved[.faceScale], base[.faceScale])
        XCTAssertGreaterThan(moved[.faceX], base[.faceX])
    }

    func testVisionAnglesArePassedThrough() throws {
        let m = try XCTUnwrap(FaceGeometry.measure(landmarks: frontalFace(), pose: HeadPose(yaw: 0.3, pitch: -0.1, roll: 0), imageSize: frame))
        XCTAssertEqual(m[.yaw], 0.3)
        XCTAssertEqual(m[.pitch], -0.1)
    }

    func testClosedEyesReadAsBlinks() throws {
        var face = frontalFace()
        face.leftEye = face.leftEye.map { CGPoint(x: $0.x, y: 400 + ($0.y - 400) * 0.2) }
        face.rightEye = face.rightEye.map { CGPoint(x: $0.x, y: 400 + ($0.y - 400) * 0.2) }
        let m = try XCTUnwrap(FaceGeometry.measure(landmarks: face, pose: noPose, imageSize: frame))
        XCTAssertTrue(m.isBlinking)
    }
}

final class CalibrationDataTests: XCTestCase {
    func testCleanerDropsWildFrames() {
        var random = SeededRandom(seed: 3)
        var samples = (0..<12).map { _ in
            GazeSample(features: (0..<Feature.count).map { _ in random.gaussian(0.01) }, u: 0.5, v: 0.5, point: 4, time: 0)
        }
        var wild = samples[0]
        wild.features[Feature.yaw.rawValue] = 0.8
        samples.append(wild)
        XCTAssertEqual(SampleCleaner.clean(samples).count, 12)
    }

    func testLearnedSamplesAreCapped() {
        var profile = CalibrationProfile()
        for i in 0..<(CalibrationProfile.maxLearnedPerScreen + 10) {
            profile.addLearned(GazeSample(features: [], u: 0, v: 0, point: GazeSample.learned, time: Double(i)), screen: "a")
        }
        XCTAssertEqual(profile.learned["a"]?.count, CalibrationProfile.maxLearnedPerScreen)
        XCTAssertEqual(profile.learned["a"]?.first?.time, 10)
    }

    func testRecalibratingForgetsThatScreensClicks() {
        var profile = CalibrationProfile()
        profile.addLearned(GazeSample(features: [], u: 0, v: 0, point: GazeSample.learned, time: 0), screen: "a")
        profile.addLearned(GazeSample(features: [], u: 0, v: 0, point: GazeSample.learned, time: 0), screen: "b")
        profile.setCalibration(ScreenCalibration(screenKey: "a", screenName: "A", calibratedAt: Date(), samples: []))
        XCTAssertNil(profile.learned["a"])
        XCTAssertEqual(profile.learned["b"]?.count, 1)
    }

    func testProfileRoundTripsThroughJSON() throws {
        var user = SyntheticUser.threeScreens()
        var profile = user.calibrate(framesPerDot: 2)
        profile.cameraID = "camera-1"
        let data = try JSONEncoder().encode(profile)
        XCTAssertEqual(try JSONDecoder().decode(CalibrationProfile.self, from: data), profile)
    }

    func testScreenPointConversions() {
        let frame = CGRect(x: -1920, y: -396, width: 1920, height: 1080)
        let point = ScreenPoint(u: 0.25, v: 0.5)
        let location = point.location(in: frame)
        XCTAssertEqual(location, CGPoint(x: -1440, y: 144))
        XCTAssertEqual(ScreenPoint(location: location, in: frame), point)
    }

    func testFindsTheScreenForARect() {
        let screens = [
            ScreenDescriptor(key: "laptop", frame: CGRect(x: 0, y: 0, width: 1728, height: 1117)),
            ScreenDescriptor(key: "above", frame: CGRect(x: 0, y: -1080, width: 1920, height: 1080)),
        ]
        XCTAssertEqual(screens.screen(for: CGRect(x: 100, y: -900, width: 800, height: 1000))?.key, "above")
        XCTAssertEqual(screens.screen(containing: CGPoint(x: 2500, y: 800))?.key, "laptop")
    }
}

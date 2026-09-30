import CoreGraphics
import Foundation

/// The numbers SightShift derives from one camera frame. Together they describe where the head
/// points (yaw, pitch and two landmark-based proxies), where the eyes point inside the head, and
/// where the head sits in front of the camera.
public enum Feature: Int, CaseIterable, Codable, Sendable {
    case yaw
    case pitch
    case noseX
    case noseY
    case contourAsymmetry
    case eyeX
    case eyeY
    case faceX
    case faceY
    case faceScale

    public static let count = allCases.count

    public var label: String {
        switch self {
        case .yaw: return "Head yaw"
        case .pitch: return "Head pitch"
        case .noseX: return "Nose offset X"
        case .noseY: return "Nose offset Y"
        case .contourAsymmetry: return "Face asymmetry"
        case .eyeX: return "Eyes X"
        case .eyeY: return "Eyes Y"
        case .faceX: return "Face position X"
        case .faceY: return "Face position Y"
        case .faceScale: return "Face size"
        }
    }

    /// The smallest spread we believe for this feature, in its own units. Anything that moved less
    /// than this during calibration is treated as noise rather than as a precise signal, which
    /// keeps a feature that barely changed from becoming a hair trigger later.
    public var minimumSpread: Double {
        switch self {
        case .yaw, .pitch: return 0.03 // radians, about 1.7°
        case .noseX, .noseY: return 0.02 // fraction of the eye distance
        case .contourAsymmetry: return 0.03
        case .eyeX, .eyeY: return 0.05 // fraction of the eye width
        case .faceX, .faceY: return 0.03 // fraction of the camera frame
        case .faceScale: return 0.006 // eye distance / frame width
        }
    }

    /// Features that describe where you sit rather than where you look.
    public var describesPosition: Bool {
        switch self {
        case .faceX, .faceY, .faceScale: return true
        default: return false
        }
    }
}

/// Landmarks for one face in image pixels, using Vision's convention (origin bottom-left, y up).
public struct FaceLandmarks: Sendable {
    public var leftEye: [CGPoint]
    public var rightEye: [CGPoint]
    public var leftPupil: CGPoint?
    public var rightPupil: CGPoint?
    public var nose: [CGPoint]
    public var faceContour: [CGPoint]

    public init(
        leftEye: [CGPoint],
        rightEye: [CGPoint],
        leftPupil: CGPoint?,
        rightPupil: CGPoint?,
        nose: [CGPoint],
        faceContour: [CGPoint]
    ) {
        self.leftEye = leftEye
        self.rightEye = rightEye
        self.leftPupil = leftPupil
        self.rightPupil = rightPupil
        self.nose = nose
        self.faceContour = faceContour
    }
}

/// Head angles reported by the face detector, in radians.
public struct HeadPose: Sendable {
    public var yaw: Double?
    public var pitch: Double?
    public var roll: Double?

    public init(yaw: Double?, pitch: Double?, roll: Double?) {
        self.yaw = yaw
        self.pitch = pitch
        self.roll = roll
    }
}

public struct FaceMeasurement: Sendable, Equatable {
    /// `Feature.count` values, indexed by `Feature.rawValue`.
    public var features: [Double]
    /// Average eye height / eye width. Drops sharply during a blink.
    public var eyeOpenness: Double
    /// Distance between the eye centres, in pixels.
    public var interocularDistance: Double

    public init(features: [Double], eyeOpenness: Double, interocularDistance: Double) {
        self.features = features
        self.eyeOpenness = eyeOpenness
        self.interocularDistance = interocularDistance
    }

    public static let blinkOpenness = 0.14

    public var isBlinking: Bool { eyeOpenness < Self.blinkOpenness }

    public subscript(_ feature: Feature) -> Double { features[feature.rawValue] }
}

public enum FaceGeometry {
    /// Turns raw landmarks into scale- and roll-independent features.
    ///
    /// Offsets are measured in a face-aligned frame: the x axis runs from one eye to the other and
    /// lengths are divided by the eye distance, so tilting your head or leaning in doesn't
    /// masquerade as looking somewhere else.
    public static func measure(landmarks: FaceLandmarks, pose: HeadPose, imageSize: CGSize) -> FaceMeasurement? {
        guard landmarks.leftEye.count >= 3, landmarks.rightEye.count >= 3,
              imageSize.width > 0, imageSize.height > 0 else { return nil }

        let eyeA = centroid(landmarks.leftEye)
        let eyeB = centroid(landmarks.rightEye)
        let across = CGPoint(x: eyeB.x - eyeA.x, y: eyeB.y - eyeA.y)
        let interocular = Double(hypot(across.x, across.y))
        guard interocular > 4 else { return nil }

        let ex = CGPoint(x: across.x / CGFloat(interocular), y: across.y / CGFloat(interocular))
        var ey = CGPoint(x: -ex.y, y: ex.x)
        if ey.y < 0 { ey = CGPoint(x: -ey.x, y: -ey.y) }
        let mid = CGPoint(x: (eyeA.x + eyeB.x) / 2, y: (eyeA.y + eyeB.y) / 2)

        func local(_ p: CGPoint) -> (x: Double, y: Double) {
            let d = CGPoint(x: p.x - mid.x, y: p.y - mid.y)
            return (Double(d.x * ex.x + d.y * ex.y) / interocular, Double(d.x * ey.x + d.y * ey.y) / interocular)
        }

        // The nose sticks out in front of the eyes, so its outline slides sideways as the head turns.
        var noseOffset = (x: 0.0, y: 0.0)
        if !landmarks.nose.isEmpty {
            noseOffset = local(centroid(landmarks.nose))
        }

        // Turning the head shows more cheek on one side: compare how far each eye sits from its face edge.
        var asymmetry = 0.0
        let contourX = landmarks.faceContour.map { local($0).x }
        if let minX = contourX.min(), let maxX = contourX.max() {
            let left = -0.5 - minX
            let right = maxX - 0.5
            if left + right > 0.2 { asymmetry = (left - right) / (left + right) }
        }

        let eyes = [
            eyeMetrics(landmarks.leftEye, pupil: landmarks.leftPupil, ex: ex, ey: ey),
            eyeMetrics(landmarks.rightEye, pupil: landmarks.rightPupil, ex: ex, ey: ey),
        ].compactMap { $0 }
        let openness = eyes.isEmpty ? 0 : eyes.map(\.openness).reduce(0, +) / Double(eyes.count)
        let gazes = eyes.compactMap(\.gaze)
        let eyeGaze = gazes.isEmpty
            ? (x: 0.0, y: 0.0)
            : (x: gazes.map(\.x).reduce(0, +) / Double(gazes.count), y: gazes.map(\.y).reduce(0, +) / Double(gazes.count))

        var values = [Double](repeating: 0, count: Feature.count)
        values[Feature.yaw.rawValue] = pose.yaw ?? asymmetry * 0.9
        values[Feature.pitch.rawValue] = pose.pitch ?? 0
        values[Feature.noseX.rawValue] = noseOffset.x
        values[Feature.noseY.rawValue] = noseOffset.y
        values[Feature.contourAsymmetry.rawValue] = asymmetry
        values[Feature.eyeX.rawValue] = eyeGaze.x
        values[Feature.eyeY.rawValue] = eyeGaze.y
        values[Feature.faceX.rawValue] = Double(mid.x / imageSize.width)
        values[Feature.faceY.rawValue] = Double(mid.y / imageSize.height)
        values[Feature.faceScale.rawValue] = interocular / Double(imageSize.width)
        guard values.allSatisfy(\.isFinite) else { return nil }

        return FaceMeasurement(features: values, eyeOpenness: openness, interocularDistance: interocular)
    }

    private struct EyeMetrics {
        var openness: Double
        var gaze: (x: Double, y: Double)?
    }

    private static func eyeMetrics(_ outline: [CGPoint], pupil: CGPoint?, ex: CGPoint, ey: CGPoint) -> EyeMetrics? {
        guard outline.count >= 3 else { return nil }
        let center = centroid(outline)
        let along = outline.map { Double(($0.x - center.x) * ex.x + ($0.y - center.y) * ex.y) }
        let up = outline.map { Double(($0.x - center.x) * ey.x + ($0.y - center.y) * ey.y) }
        guard let minA = along.min(), let maxA = along.max(), let minU = up.min(), let maxU = up.max() else { return nil }
        let width = maxA - minA
        guard width > 1.5 else { return nil }
        var metrics = EyeMetrics(openness: (maxU - minU) / width, gaze: nil)
        if let pupil {
            let d = CGPoint(x: pupil.x - center.x, y: pupil.y - center.y)
            metrics.gaze = (Double(d.x * ex.x + d.y * ex.y) / width, Double(d.x * ey.x + d.y * ey.y) / width)
        }
        return metrics
    }

    static func centroid(_ points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        var x: CGFloat = 0
        var y: CGFloat = 0
        for p in points {
            x += p.x
            y += p.y
        }
        return CGPoint(x: x / CGFloat(points.count), y: y / CGFloat(points.count))
    }
}

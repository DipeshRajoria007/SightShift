import CoreVideo
import SightShiftCore
import Vision

/// What one camera frame told us. The image itself is gone by the time this exists.
struct FaceFrame {
    let time: Double
    let measurement: FaceMeasurement?
    let faceCount: Int
    let confidence: Double

    static func empty(at time: Double, faces: Int = 0) -> FaceFrame {
        FaceFrame(time: time, measurement: nil, faceCount: faces, confidence: 0)
    }
}

/// Finds the user's face with Apple's Vision framework and turns it into features.
/// Used only from the camera's frame queue.
final class FaceTracker {
    private let rectangles = VNDetectFaceRectanglesRequest()
    private let landmarks = VNDetectFaceLandmarksRequest()
    private var lastBox: CGRect?

    init() {
        rectangles.revision = VNDetectFaceRectanglesRequestRevision3
        landmarks.revision = VNDetectFaceLandmarksRequestRevision3
        landmarks.constellation = .constellation76Points
    }

    func process(_ pixelBuffer: CVPixelBuffer, time: Double) -> FaceFrame {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([rectangles])
        } catch {
            return .empty(at: time)
        }
        let faces = rectangles.results ?? []
        guard let face = chooseFace(faces) else {
            lastBox = nil
            return .empty(at: time)
        }
        lastBox = face.boundingBox

        landmarks.inputFaceObservations = [face]
        do {
            try handler.perform([landmarks])
        } catch {
            return .empty(at: time, faces: faces.count)
        }
        guard let observation = landmarks.results?.first, let points = observation.landmarks else {
            return .empty(at: time, faces: faces.count)
        }

        let size = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        func region(_ region: VNFaceLandmarkRegion2D?) -> [CGPoint] {
            region?.pointsInImage(imageSize: size) ?? []
        }
        let input = FaceLandmarks(
            leftEye: region(points.leftEye),
            rightEye: region(points.rightEye),
            leftPupil: region(points.leftPupil).first,
            rightPupil: region(points.rightPupil).first,
            nose: region(points.nose),
            faceContour: region(points.faceContour)
        )
        let pose = HeadPose(yaw: face.yaw?.doubleValue, pitch: face.pitch?.doubleValue, roll: face.roll?.doubleValue)
        return FaceFrame(
            time: time,
            measurement: FaceGeometry.measure(landmarks: input, pose: pose, imageSize: size),
            faceCount: faces.count,
            confidence: Double(observation.confidence)
        )
    }

    /// The largest face, unless the face we were already following is still there and not much smaller.
    private func chooseFace(_ faces: [VNFaceObservation]) -> VNFaceObservation? {
        guard let largest = faces.max(by: { $0.boundingBox.area < $1.boundingBox.area }) else { return nil }
        guard faces.count > 1, let lastBox else { return largest }
        let continuing = faces.max { $0.boundingBox.overlapRatio(with: lastBox) < $1.boundingBox.overlapRatio(with: lastBox) }
        if let continuing, continuing.boundingBox.overlapRatio(with: lastBox) > 0.3,
           continuing.boundingBox.area > largest.boundingBox.area * 0.6 {
            return continuing
        }
        return largest
    }
}

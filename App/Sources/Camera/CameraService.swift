import AVFoundation
import CoreMedia

struct CameraDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let isBuiltIn: Bool
}

/// Runs the camera at 720p, no faster than 15 frames a second, and hands each frame to the face
/// tracker. Frames only ever live in memory for the duration of one analysis.
final class CameraService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    enum State: Equatable {
        case stopped
        case running(id: String, name: String)
        case failed(String)
    }

    static let maxFramesPerSecond = 15.0

    /// Called on the frame queue for every analysed frame. Set before calling `start`.
    var onFrame: ((FaceFrame) -> Void)?
    /// Called on the main queue.
    var onStateChange: ((State) -> Void)?
    /// Called on the main queue when a camera is plugged in.
    var onDeviceConnected: (() -> Void)?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "app.sightshift.camera")
    private let frameQueue = DispatchQueue(label: "app.sightshift.frames", qos: .userInitiated)
    private let output = AVCaptureVideoDataOutput()
    private let tracker = FaceTracker()
    private var input: AVCaptureDeviceInput?
    private var outputAdded = false
    private var lastFrameTime = 0.0
    private var failed = false // session queue
    private var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { [weak self] note in
            let error = note.userInfo?[AVCaptureSessionErrorKey] as? Error
            self?.sessionQueue.async {
                self?.report(.failed(error?.localizedDescription ?? "The camera stopped unexpectedly."))
            }
        })
        observers.append(center.addObserver(forName: AVCaptureDevice.wasConnectedNotification, object: nil, queue: .main) { [weak self] _ in
            self?.onDeviceConnected?()
        })
        observers.append(center.addObserver(forName: AVCaptureDevice.wasDisconnectedNotification, object: nil, queue: nil) { [weak self] note in
            guard let self, let device = note.object as? AVCaptureDevice else { return }
            self.sessionQueue.async {
                guard self.input?.device.uniqueID == device.uniqueID else { return }
                self.session.stopRunning()
                self.report(.failed("\(device.localizedName) was disconnected."))
            }
        })
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    static func availableDevices() -> [CameraDevice] {
        discovery().devices.map {
            CameraDevice(id: $0.uniqueID, name: $0.localizedName, isBuiltIn: $0.deviceType == .builtInWideAngleCamera)
        }
    }

    /// The built-in camera when there is one: it faces you, unlike a phone lying on the desk.
    static func defaultDevice() -> AVCaptureDevice? {
        let devices = discovery().devices
        return devices.first { $0.deviceType == .builtInWideAngleCamera } ?? devices.first ?? AVCaptureDevice.default(for: .video)
    }

    private static func discovery() -> AVCaptureDevice.DiscoverySession {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        )
    }

    func start(preferredID: String?) {
        sessionQueue.async { [self] in
            let device = preferredID.flatMap { AVCaptureDevice(uniqueID: $0) } ?? Self.defaultDevice()
            guard let device else {
                report(.failed("No camera found."))
                return
            }
            if input?.device.uniqueID == device.uniqueID, session.isRunning { return }

            // Centre Stage crops and pans to follow the face, which would hide head movement.
            if AVCaptureDevice.isCenterStageEnabled {
                AVCaptureDevice.centerStageControlMode = .app
                AVCaptureDevice.isCenterStageEnabled = false
            }

            session.beginConfiguration()
            if let input {
                session.removeInput(input)
                self.input = nil
            }
            do {
                let newInput = try AVCaptureDeviceInput(device: device)
                guard session.canAddInput(newInput) else {
                    session.commitConfiguration()
                    report(.failed("\(device.localizedName) is busy or unavailable."))
                    return
                }
                session.addInput(newInput)
                input = newInput
            } catch {
                session.commitConfiguration()
                report(.failed(error.localizedDescription))
                return
            }
            // Which presets are possible depends on the input, so pick one after adding it.
            session.sessionPreset = session.canSetSessionPreset(.hd1280x720) ? .hd1280x720 : .high
            if !outputAdded {
                output.alwaysDiscardsLateVideoFrames = true
                output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
                output.setSampleBufferDelegate(self, queue: frameQueue)
                if session.canAddOutput(output) {
                    session.addOutput(output)
                    outputAdded = true
                }
            }
            session.commitConfiguration()

            limitFrameRate(of: device)
            if !session.isRunning { session.startRunning() }
            // Some cameras pick their own rate when the session starts.
            limitFrameRate(of: device)
            report(.running(id: device.uniqueID, name: device.localizedName))
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            guard session.isRunning || failed else { return }
            if session.isRunning { session.stopRunning() }
            report(.stopped)
        }
    }

    private func limitFrameRate(of device: AVCaptureDevice) {
        let rate = Self.maxFramesPerSecond
        guard device.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= rate && rate <= $0.maxFrameRate }) else {
            return // frames are still throttled in `captureOutput`
        }
        do {
            try device.lockForConfiguration()
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(rate))
            device.unlockForConfiguration()
        } catch {
            // Not fatal: `captureOutput` drops the extra frames.
        }
    }

    /// Called on the session queue.
    private func report(_ state: State) {
        if case .failed = state { failed = true } else { failed = false }
        DispatchQueue.main.async { [weak self] in self?.onStateChange?(state) }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = ProcessInfo.processInfo.systemUptime
        // Three quarters of a frame interval: 15 fps passes despite timing jitter, 30 fps is halved.
        guard now - lastFrameTime >= 0.75 / Self.maxFramesPerSecond else { return }
        lastFrameTime = now
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let frame = tracker.process(pixelBuffer, time: now)
        onFrame?(frame)
    }
}

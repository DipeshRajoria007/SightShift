import AppKit
import SightShiftCore
import SwiftUI

/// What one screen shows during calibration.
@MainActor
final class CalibrationScreenModel: ObservableObject {
    @Published var isActive = false
    @Published var title = ""
    @Published var subtitle = ""
    @Published var warning: String?
    @Published var dot = ScreenPoint(u: 0.5, v: 0.5)
    @Published var dotVisible = false
    @Published var progress = 0.0
    @Published var result: [String] = []
}

/// Shows a dot at nine positions on each screen in turn and records the face while you look at it.
@MainActor
final class CalibrationController {
    /// Snake order, so the dot never jumps across the whole screen.
    static let grid: [ScreenPoint] = [
        ScreenPoint(u: 0.08, v: 0.08), ScreenPoint(u: 0.5, v: 0.08), ScreenPoint(u: 0.92, v: 0.08),
        ScreenPoint(u: 0.92, v: 0.5), ScreenPoint(u: 0.5, v: 0.5), ScreenPoint(u: 0.08, v: 0.5),
        ScreenPoint(u: 0.08, v: 0.92), ScreenPoint(u: 0.5, v: 0.92), ScreenPoint(u: 0.92, v: 0.92),
    ]
    private static let framesPerDot = 12
    private static let minimumSamplesPerScreen = 50

    /// Called with the finished calibrations and the run they came from. Call `showResult` with
    /// the same run number afterwards to wrap up.
    var onFinish: (([ScreenCalibration], [DisplayInfo], Int) -> Void)?
    /// Called once the calibration windows are gone, finished or not.
    var onClose: (() -> Void)?

    private(set) var isRunning = false
    private var windows: [NSWindow] = []
    private var models: [String: CalibrationScreenModel] = [:]
    private var task: Task<Void, Never>?
    private var keyMonitor: Any?
    private var collecting: (screen: String, dot: Int, point: ScreenPoint)?
    private var samples: [String: [GazeSample]] = [:]
    private var samplesAtDot = 0
    private var lastFaceTime = -Double.infinity
    private var lastFrameTime = -Double.infinity
    private var session = 0

    private static var now: Double { ProcessInfo.processInfo.systemUptime }

    func start(displays: [DisplayInfo], allDisplays: [DisplayInfo]) {
        guard !isRunning, !displays.isEmpty else { return }
        isRunning = true
        session += 1
        samples = [:]
        lastFrameTime = Self.now // the camera gets a few seconds to start
        for display in allDisplays {
            let model = CalibrationScreenModel()
            models[display.key] = model
            windows.append(makeWindow(for: display, model: model))
        }
        NSApp.activate()
        windows.first?.makeKeyAndOrderFront(nil)
        windows.forEach { $0.orderFrontRegardless() }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { // Esc
                self.cancel()
                return nil
            }
            if event.keyCode == 36 || event.keyCode == 49 { // Return or Space dismiss the result screen
                if self.task == nil { self.close() }
                return nil
            }
            return event
        }
        task = Task { [weak self] in await self?.run(displays: displays) }
    }

    func ingest(_ frame: FaceFrame) {
        guard isRunning else { return }
        lastFrameTime = frame.time
        if frame.measurement != nil { lastFaceTime = frame.time }
        guard let collecting, let measurement = frame.measurement, !measurement.isBlinking else { return }
        samples[collecting.screen, default: []].append(GazeSample(
            features: measurement.features,
            u: collecting.point.u,
            v: collecting.point.v,
            point: collecting.dot,
            time: Date().timeIntervalSinceReferenceDate
        ))
        samplesAtDot += 1
    }

    func cancel() {
        task?.cancel()
        task = nil
        close()
    }

    /// Stops early and says why, for instance when the camera fails.
    func abort(reason: String) {
        guard isRunning, task != nil else { return }
        task?.cancel()
        task = nil
        collecting = nil
        showResult(title: "Calibration stopped", lines: [reason], session: session)
    }

    /// Replaces the dots with a short summary, then closes (Return, Space or Esc close it sooner).
    func showResult(title: String, lines: [String], session: Int) {
        guard isRunning, session == self.session else { return }
        for model in models.values {
            model.dotVisible = false
            model.warning = nil
            model.title = title
            model.subtitle = "Press Return to close"
            model.result = lines
        }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard let self, self.session == session else { return }
            self.close()
        }
    }

    private func close() {
        guard isRunning else { return }
        isRunning = false
        collecting = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        windows.forEach { $0.orderOut(nil) }
        windows = []
        models = [:]
        onClose?()
    }

    private func run(displays: [DisplayInfo]) async {
        for (index, display) in displays.enumerated() {
            guard let model = models[display.key] else { continue }
            for (key, other) in models where key != display.key {
                other.isActive = false
                other.dotVisible = false
                other.warning = nil
                other.title = "Look at \(display.name)"
                other.subtitle = "Screen \(index + 1) of \(displays.count)"
            }
            model.isActive = true
            model.title = "Turn to face this screen"
            model.subtitle = "Screen \(index + 1) of \(displays.count) · follow the dot with your eyes · Esc cancels"
            model.dot = Self.grid[0]
            model.progress = 0
            model.dotVisible = true
            guard await pause(2.2) else { return }

            for (dotIndex, point) in Self.grid.enumerated() {
                model.dot = point
                model.progress = 0
                guard await pause(0.9) else { return } // travel, then let the eyes settle
                collecting = (display.key, dotIndex, point)
                samplesAtDot = 0
                // Time only counts while your face is visible; the dot waits for you otherwise.
                var seenFor = 0.0
                var waited = 0.0
                while true {
                    guard await pause(0.05) else { return }
                    waited += 0.05
                    let cameraSilent = Self.now - lastFrameTime > 3
                    let faceVisible = Self.now - lastFaceTime < 0.8
                    if faceVisible { seenFor += 0.05 }
                    model.progress = min(1, Double(samplesAtDot) / Double(Self.framesPerDot))
                    model.warning = faceVisible ? nil
                        : cameraSilent ? "The camera isn't sending pictures."
                        : "Can't see your face. Make sure the camera has a clear view of you."
                    if samplesAtDot >= Self.framesPerDot, seenFor >= 0.8 { break }
                    if seenFor > 4, samplesAtDot >= 5 { break }
                    if waited > 20 {
                        abort(reason: cameraSilent
                            ? "The camera isn't sending pictures. Check that no other app is using it, then try again."
                            : "SightShift couldn't see your face for long enough. Check the lighting and that the camera faces you, then try again.")
                        return
                    }
                }
                collecting = nil
            }
            model.dotVisible = false
            model.isActive = false
            model.warning = nil
        }
        task = nil

        let finished = displays.compactMap { display -> ScreenCalibration? in
            guard let list = samples[display.key], list.count >= Self.minimumSamplesPerScreen else { return nil }
            return ScreenCalibration(screenKey: display.key, screenName: display.name, calibratedAt: Date(), samples: list)
        }
        for model in models.values {
            model.title = "Crunching the numbers…"
            model.subtitle = ""
        }
        onFinish?(finished, displays, session)
    }

    private func pause(_ seconds: Double) async -> Bool {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        return !Task.isCancelled && isRunning
    }

    private func makeWindow(for display: DisplayInfo, model: CalibrationScreenModel) -> NSWindow {
        let frame = Displays.cocoaRect(fromGlobal: display.frame)
        let window = CalibrationWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.setFrame(frame, display: false)
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: CalibrationView(model: model))
        return window
    }
}

private final class CalibrationWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private struct CalibrationView: View {
    @ObservedObject var model: CalibrationScreenModel

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(model.isActive ? 0.9 : 0.78)
                VStack(spacing: 10) {
                    Text(model.title)
                        .font(.system(size: model.isActive ? 28 : 22, weight: .semibold))
                    if !model.subtitle.isEmpty {
                        Text(model.subtitle)
                            .font(.system(size: 15))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    if let warning = model.warning {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.orange)
                            .padding(.top, 6)
                    }
                    ForEach(model.result, id: \.self) { line in
                        Text(line)
                            .font(.system(size: 16))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 720)
                .position(x: geometry.size.width / 2, y: geometry.size.height * 0.3)

                if model.dotVisible {
                    CalibrationDot(progress: model.progress)
                        .position(x: geometry.size.width * model.dot.u, y: geometry.size.height * model.dot.v)
                        .animation(.easeInOut(duration: 0.5), value: model.dot)
                }
            }
        }
        .ignoresSafeArea()
    }
}

private struct CalibrationDot: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.25), lineWidth: 4)
                .frame(width: 44, height: 44)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 44, height: 44)
                .animation(.linear(duration: 0.1), value: progress)
            Circle()
                .fill(.white)
                .frame(width: 12, height: 12)
        }
    }
}

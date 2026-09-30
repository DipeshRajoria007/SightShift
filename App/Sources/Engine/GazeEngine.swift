import AppKit
import SightShiftCore

/// Turns face measurements into focus changes.
///
/// Each frame: smooth the features, ask the model which screen (and where on it) you're
/// looking at, wait for that answer to settle, and then, once you aren't typing or using the
/// mouse, move focus there.
@MainActor
final class GazeEngine {
    /// Extra head turn needed on top of the chosen threshold; also what makes going back need a
    /// slightly bigger turn than going there.
    static let hysteresis = 0.08

    var settings = AppSettings.current() {
        didSet {
            if !settings.showGazeDot { overlay.hide() }
            if settings.sameScreenFocus != oldValue.sameScreenFocus { updateLayoutWanted() }
        }
    }
    var displays: [DisplayInfo] = [] {
        didSet { resetTracking() }
    }
    /// False while paused, asleep, calibrating or missing permissions.
    var isActing = false {
        didSet {
            if !isActing {
                pendingScreen = nil
                pendingTarget = nil
                overlay.hide()
            }
            updateLayoutWanted()
        }
    }
    var isCalibrating = false

    /// Receives every frame while calibration runs.
    var calibrationSink: ((FaceFrame) -> Void)?
    /// A click taught us something: add this sample for that screen.
    var onLearnedSample: ((GazeSample, String) -> Void)?
    /// Clicks keep landing on screens the model didn't expect.
    var onAccuracyConcern: (() -> Void)?

    private(set) var model: GazeModel?
    private let worker: FocusWorker
    private let activity: ActivityMonitor
    private let overlay: GazeDotOverlay
    private let status: EngineStatus

    private var smoother = GazeEngine.makeSmoother()
    private var dotFilterX = OneEuroFilter(minCutoff: 0.6, beta: 0.004)
    private var dotFilterY = OneEuroFilter(minCutoff: 0.6, beta: 0.004)
    private var screenTracker = DwellTracker<String>()
    private var targetTracker = DwellTracker<String>()
    private var pendingScreen: PendingMove<String>?
    private var pendingTarget: PendingMove<String>?
    private var focus: FocusSnapshot?
    private var layout: SameScreenLayout?
    private var recentFrames: [FaceFrame] = []
    private var lastOpenEyes: (x: Double, y: Double)?
    private var lastFaceTime = -Double.infinity
    private var lastMoveTime = -Double.infinity
    private var rememberedPointer: [String: CGPoint] = [:]
    private var clickAgreement: [Bool] = []
    private var raisedAccuracyConcern = false
    private var frameTimes: [Double] = []
    private var lastPublish = 0.0
    private var lastHold: FocusHold?
    private var lastGazePoint: ScreenPoint?

    init(worker: FocusWorker, activity: ActivityMonitor, overlay: GazeDotOverlay, status: EngineStatus) {
        self.worker = worker
        self.activity = activity
        self.overlay = overlay
        self.status = status
        activity.onClick = { [weak self] point, time in self?.learnFromClick(at: point, time: time) }
    }

    private static func makeSmoother() -> OneEuroVectorFilter {
        OneEuroVectorFilter(scales: Feature.allCases.map(\.minimumSpread), minCutoff: 1.5, beta: 0.05)
    }

    /// - Parameter keepTracking: keep the settled screen and any pending move, as when the model
    ///   was only refined by a click. A fresh calibration starts over.
    func setModel(_ model: GazeModel?, keepTracking: Bool) {
        self.model = model
        let stillKnown = screenTracker.stable.map { model?.screenKeys.contains($0) ?? false } ?? true
        if !keepTracking || !stillKnown { resetTracking() }
        status.gateRadius = model?.classifier.gateRadius ?? 0
        updateLayoutWanted()
    }

    func focusChanged(_ snapshot: FocusSnapshot?) {
        focus = snapshot
        status.focusAppName = snapshot?.appName
        status.focusScreenName = focusScreenKey().flatMap(displayName)
    }

    func layoutChanged(_ layout: SameScreenLayout?) {
        self.layout = layout
        status.paneCount = layout?.paneCount ?? 0
    }

    func log(_ line: String) {
        status.append(line)
    }

    private func resetTracking() {
        screenTracker.reset()
        targetTracker.reset()
        pendingScreen = nil
        pendingTarget = nil
        smoother.reset()
    }

    private func updateLayoutWanted() {
        worker.setLayoutWanted(isActing && settings.sameScreenFocus && model != nil)
    }

    // MARK: Frames

    func ingest(_ frame: FaceFrame) {
        noteFrameRate(frame.time)
        recentFrames.append(frame)
        if let first = recentFrames.first, frame.time - first.time > 1.5 {
            recentFrames.removeAll { frame.time - $0.time > 1.5 }
        }
        if isCalibrating {
            calibrationSink?(frame)
            publish(frame: frame, estimate: nil, features: frame.measurement?.features)
            return
        }

        guard let measurement = frame.measurement else {
            _ = screenTracker.update(nil, now: frame.time, dwell: settings.screenSwitchDelay)
            _ = targetTracker.update(nil, now: frame.time, dwell: settings.paneDelay)
            if frame.time - lastFaceTime > 0.5 { overlay.hide() }
            if frame.time - lastFaceTime > 1 {
                // Whatever you were about to do when you looked away is stale by the time you're back.
                pendingScreen = nil
                pendingTarget = nil
            }
            publish(frame: frame, estimate: nil, features: nil)
            return
        }
        lastFaceTime = frame.time

        // During a blink the pupils can't be found; keep the last open-eye reading.
        var features = measurement.features
        if measurement.isBlinking, let eyes = lastOpenEyes {
            features[Feature.eyeX.rawValue] = eyes.x
            features[Feature.eyeY.rawValue] = eyes.y
        } else if !measurement.isBlinking {
            lastOpenEyes = (features[Feature.eyeX.rawValue], features[Feature.eyeY.rawValue])
        }
        let smoothed = smoother.filter(features, time: frame.time)

        guard let model else {
            publish(frame: frame, estimate: nil, features: smoothed)
            return
        }

        let estimate = model.estimate(smoothed, current: screenTracker.stable, threshold: settings.headTurnThreshold, hysteresis: Self.hysteresis)
        if let transition = screenTracker.update(estimate.screen, now: frame.time, dwell: settings.screenSwitchDelay) {
            pendingScreen = PendingMove(transition, lastKeyDown: activity.times(now: frame.time).lastKeyDown)
            pendingTarget = nil
            targetTracker.reset()
            log("Looking at \(displayName(transition.target) ?? "a screen")")
        }

        let gaze = gazeLocation(model: model, features: smoothed, estimate: estimate, time: frame.time)
        if settings.showGazeDot, isActing, let gaze, let display = displays.first(where: { $0.key == gaze.screen }) {
            overlay.show(at: gaze.location, on: display)
        } else {
            overlay.hide()
        }

        if isActing {
            act(now: frame.time, gaze: gaze, onScreen: estimate.screen != nil)
        }
        publish(frame: frame, estimate: estimate, features: smoothed)
    }

    /// Where on the settled screen you're looking, in global coordinates.
    private func gazeLocation(model: GazeModel, features: [Double], estimate: GazeEstimate, time: Double) -> (screen: String, location: CGPoint)? {
        guard estimate.screen != nil, let key = screenTracker.stable,
              let display = displays.first(where: { $0.key == key }),
              let point = model.point(on: key, features: features), point.isWithin(margin: 0.1) else { return nil }
        let raw = point.clamped.location(in: display.frame)
        let location = CGPoint(x: dotFilterX.filter(raw.x, time: time), y: dotFilterY.filter(raw.y, time: time))
        lastGazePoint = point
        return (key, location)
    }

    // MARK: Decisions

    private func act(now: Double, gaze: (screen: String, location: CGPoint)?, onScreen: Bool) {
        note(decide(now: now, gaze: gaze, onScreen: onScreen))
    }

    /// Moves focus if a settled gaze change is due. Returns what's holding a move back, if anything.
    private func decide(now: Double, gaze: (screen: String, location: CGPoint)?, onScreen: Bool) -> FocusHold? {
        // While one of SightShift's own windows is active (settings, diagnostics) it only watches.
        if isSightShiftWindowActive {
            pendingScreen = nil
            pendingTarget = nil
            return nil
        }
        let times = activity.times(now: now)
        let focusScreen = focusScreenKey()

        if var move = pendingScreen {
            if move.target != screenTracker.stable || move.target == focusScreen || now - move.transition.settledAt > 30 {
                pendingScreen = nil
            } else if let elsewhere = screenTracker.pending, elsewhere != move.target {
                // The gaze has already moved on; see where it settles before doing anything.
                return nil
            } else {
                let verdict = move.verdict(now: now, activity: times, settings: settings.guards)
                pendingScreen = move
                switch verdict {
                case .perform:
                    pendingScreen = nil
                    lastMoveTime = now
                    switchScreen(to: move.target, pointerJustUsed: now - times.lastPointer < 5)
                    return nil
                case .wait(let hold):
                    return hold
                case .cancel:
                    pendingScreen = nil
                    log("Stayed put: you kept typing while looking at \(displayName(move.target) ?? "another screen")")
                    return nil
                }
            }
        }

        // Windows and panes on the screen that already has focus.
        guard settings.sameScreenFocus, let focusScreen, screenTracker.stable == focusScreen,
              let layout, layout.screenKey == focusScreen else {
            _ = targetTracker.update(nil, now: now, dwell: settings.paneDelay)
            pendingTarget = nil
            return nil
        }
        guard let gaze, onScreen, gaze.screen == focusScreen, now - lastMoveTime > 0.8 else {
            _ = targetTracker.update(nil, now: now, dwell: settings.paneDelay)
            return nil
        }
        let candidate = TargetSelector.select(point: gaze.location, targets: layout.targets, current: layout.currentTargetID)
        if let transition = targetTracker.update(candidate, now: now, dwell: settings.paneDelay) {
            pendingTarget = PendingMove(transition, lastKeyDown: times.lastKeyDown)
        }
        guard var move = pendingTarget else { return nil }
        if move.target != targetTracker.stable || move.target == layout.currentTargetID || now - move.transition.settledAt > 30 {
            pendingTarget = nil
            return nil
        }
        if let elsewhere = targetTracker.pending, elsewhere != move.target { return nil }
        let verdict = move.verdict(now: now, activity: times, settings: settings.guards)
        pendingTarget = move
        switch verdict {
        case .perform:
            pendingTarget = nil
            lastMoveTime = now
            worker.focusTarget(move.target, allowClick: settings.clickToFocusPanes)
            return nil
        case .wait(let hold):
            return hold
        case .cancel:
            pendingTarget = nil
            return nil
        }
    }

    private func switchScreen(to key: String, pointerJustUsed: Bool) {
        // Remember where the pointer was, so coming back to this screen puts it there again.
        let cursor = Displays.cursorLocation
        if let here = displays.first(where: { $0.frame.contains(cursor) }), here.key != key {
            rememberedPointer[here.key] = cursor
        }
        worker.switchToScreen(key, movePointer: settings.movePointer, rememberedPointer: rememberedPointer[key], pointerJustUsed: pointerJustUsed)
    }

    private var isSightShiftWindowActive: Bool {
        focus?.isSightShift == true && NSApp.keyWindow != nil
    }

    /// The screen that has keyboard focus: the focused window's, or the pointer's when nothing
    /// has focus (say, the desktop).
    private func focusScreenKey() -> String? {
        if let key = focus?.screenKey, focus?.isSightShift != true { return key }
        return displays.map(\.descriptor).screen(containing: Displays.cursorLocation)?.key
    }

    private func note(_ hold: FocusHold?) {
        guard hold != lastHold else { return }
        lastHold = hold
        switch hold {
        case .typing?: status.waitingFor = "Waiting for typing to pause"
        case .pointer?: status.waitingFor = "Waiting for the mouse to rest"
        case nil: status.waitingFor = nil
        }
    }

    // MARK: Learning

    private func learnFromClick(at point: CGPoint, time: Double) {
        guard settings.learnFromClicks, isActing, !isSightShiftWindowActive, let model,
              let display = displays.first(where: { $0.frame.contains(point) }),
              let target = model.screenKeys.firstIndex(of: display.key) else { return }

        // You look where you click. Use the frames just before the click, if the head was still.
        let measurements = recentFrames
            .filter { $0.time >= time - 0.35 && $0.time <= time + 0.05 }
            .compactMap(\.measurement)
            .filter { !$0.isBlinking }
        guard measurements.count >= 2 else { return }
        let yaws = measurements.map { $0[.yaw] }
        guard let minYaw = yaws.min(), let maxYaw = yaws.max(), maxYaw - minYaw < 0.06 else { return }
        let features = (0..<Feature.count).map { index in
            measurements.map { $0.features[index] }.reduce(0, +) / Double(measurements.count)
        }

        let evaluation = model.classifier.evaluate(features)
        let agrees = evaluation.nearest == target
        clickAgreement.append(agrees)
        if clickAgreement.count > 30 { clickAgreement.removeFirst(clickAgreement.count - 30) }
        if clickAgreement.count == 30, !raisedAccuracyConcern,
           Double(clickAgreement.filter { $0 }.count) / 30 < 0.6 {
            raisedAccuracyConcern = true
            onAccuracyConcern?()
        }

        // A click far from the clicked screen was probably made without looking at it.
        if !agrees {
            guard evaluation.isOnScreen,
                  model.classifier.progress(of: evaluation, from: evaluation.nearest, toward: target) >= 0.3 else { return }
        }
        let location = ScreenPoint(location: point, in: display.frame)
        onLearnedSample?(
            GazeSample(features: features, u: location.u, v: location.v, point: GazeSample.learned, time: Date().timeIntervalSinceReferenceDate),
            display.key
        )
    }

    // MARK: Status

    private func noteFrameRate(_ time: Double) {
        frameTimes.append(time)
        frameTimes.removeAll { time - $0 > 2 }
    }

    private func displayName(_ key: String) -> String? {
        displays.first { $0.key == key }?.name
    }

    private func publish(frame: FaceFrame, estimate: GazeEstimate?, features: [Double]?) {
        let interval = status.isObserved ? 0.1 : 0.5
        guard frame.time - lastPublish >= interval else { return }
        lastPublish = frame.time

        status.faceVisible = frame.measurement != nil
        status.framesPerSecond = frameTimes.count > 1 ? Double(frameTimes.count - 1) / max(0.001, frameTimes.last! - frameTimes.first!) : 0
        status.gazeScreenName = screenTracker.stable.flatMap(displayName)
        status.focusScreenName = focusScreenKey().flatMap(displayName)
        guard status.isObserved else { return }
        status.features = features ?? []
        status.gazePoint = lastGazePoint
        if let estimate, let model {
            status.nearestScreenName = displayName(estimate.nearest)
            status.onScreen = estimate.screen != nil
            status.gateDistance = estimate.evaluation.gateDistance
            status.scores = model.screenKeys.enumerated().map { index, key in
                EngineStatus.ScreenScore(key: key, name: displayName(key) ?? key, distance: estimate.evaluation.distances[index])
            }
        } else {
            status.scores = []
            status.onScreen = false
        }
    }
}

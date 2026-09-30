import AppKit
import AVFoundation
import SightShiftCore
import SwiftUI

/// Owns every part of the app and decides when each one runs.
@MainActor
final class AppController: NSObject, ObservableObject {
    @Published private(set) var isPaused = false
    @Published private(set) var isSuspended = false
    @Published private(set) var accessibilityTrusted = AX.isTrusted
    @Published private(set) var cameraStatus = Permissions.cameraStatus
    @Published private(set) var displays: [DisplayInfo] = []
    @Published private(set) var profile = CalibrationProfile()
    @Published private(set) var report: TrainingReport?
    @Published private(set) var hasModel = false
    @Published private(set) var isCalibrating = false
    @Published private(set) var cameraState = CameraService.State.stopped

    let status = EngineStatus()
    private(set) var settings = AppSettings.current()

    private let store = ProfileStore()
    private let camera = CameraService()
    private let worker = FocusWorker()
    private let activity = ActivityMonitor()
    private let systemEvents = SystemEvents()
    private let overlay = GazeDotOverlay()
    private let calibration = CalibrationController()
    private let presenter = WindowPresenter()
    private lazy var engine = GazeEngine(worker: worker, activity: activity, overlay: overlay, status: status)
    private let trainingQueue = DispatchQueue(label: "app.sightshift.training", qos: .utility)
    private var statusMenu: StatusMenu?
    private var hotKey: HotKey?
    private var observers: [NSObjectProtocol] = []
    private var permissionTimer: Timer?
    private var modelGeneration = 0
    private var retrainScheduled = false
    private var saveScheduled = false
    private var diagnosticsOpen = false
    private var notifiedScreens: Set<String> = []
    private var notifiedCameraChange = false
    private var cameraRetries = 0

    // MARK: Lifecycle

    func start() {
        displays = Displays.current()
        profile = store.load() ?? CalibrationProfile()

        engine.settings = settings
        engine.displays = displays
        engine.calibrationSink = { [weak self] frame in self?.calibration.ingest(frame) }
        engine.onLearnedSample = { [weak self] sample, screen in self?.learn(sample, screen: screen) }
        engine.onAccuracyConcern = {
            Notifier.post(
                id: "accuracy",
                title: "SightShift keeps guessing wrong",
                body: "Your clicks often land on a screen it didn't expect. Recalibrating from the menu bar takes about 20 seconds per screen."
            )
        }
        overlay.configure(displays: displays)

        camera.onFrame = { @Sendable [weak self] frame in
            Task { @MainActor in self?.engine.ingest(frame) }
        }
        camera.onStateChange = { [weak self] state in self?.cameraStateChanged(state) }
        camera.onDeviceConnected = { [weak self] in
            self?.cameraRetries = 0
            self?.updateActivity()
        }

        worker.callbacks = FocusWorker.Callbacks(
            focusChanged: { [weak self] snapshot in self?.engine.focusChanged(snapshot) },
            layoutChanged: { [weak self] layout in self?.engine.layoutChanged(layout) },
            log: { [weak self] line in self?.engine.log(line) },
            syntheticClick: { [weak self] time in self?.activity.noteSyntheticClick(at: time) }
        )
        worker.update(options: FocusWorker.Options(electronPanes: settings.electronPanes))
        worker.start(displays: displays)
        activity.start()
        systemEvents.onChange = { [weak self] suspended in
            self?.isSuspended = suspended
            self?.engine.log(suspended ? "Paused while the Mac is locked or asleep" : "Back")
            self?.updateActivity()
        }
        systemEvents.start()

        calibration.onFinish = { [weak self] calibrations, requested, run in
            self?.calibrationFinished(calibrations, requested: requested, run: run)
        }
        calibration.onClose = { [weak self] in
            guard let self else { return }
            self.isCalibrating = false
            self.updateActivity()
            self.presenter.handBackFocus()
        }

        statusMenu = StatusMenu(controller: self)
        registerHotKey()
        observeChanges()
        retrain(validate: true)
        updateActivity()

        if !isSetUp {
            showOnboarding()
        }
    }

    func shutdown() {
        camera.stop()
        worker.stop()
        activity.stop()
        store.saveNow(profile)
    }

    private func observeChanges() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.settingsChanged() }
        })
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.displaysChanged() }
        })
        // SightShift can end up active with nothing to type into: after the About panel closes,
        // a notification is clicked, or it's opened from Finder. Hand focus back then.
        for name in [NSApplication.didBecomeActiveNotification, NSWindow.willCloseNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self, !self.isCalibrating else { return }
                    self.presenter.handBackFocus()
                }
            })
        }
        // Permissions can change in System Settings at any time.
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissions() }
        }
    }

    // MARK: State

    /// Starts or stops the camera and the focus engine to match the current state.
    private func updateActivity() {
        let cameraAllowed = cameraStatus == .authorized && !isPaused && !isSuspended
        if cameraAllowed, (hasModel && accessibilityTrusted) || isCalibrating || diagnosticsOpen {
            camera.start(preferredID: settings.cameraID)
        } else {
            camera.stop()
            status.faceVisible = false
        }
        engine.isCalibrating = isCalibrating
        engine.isActing = cameraAllowed && accessibilityTrusted && hasModel && !isCalibrating
        statusMenu?.refresh()
    }

    func refreshPermissions() {
        let trusted = AX.isTrusted
        let camera = Permissions.cameraStatus
        guard trusted != accessibilityTrusted || camera != cameraStatus else { return }
        if trusted, !accessibilityTrusted {
            activity.stop()
            activity.start()
        }
        accessibilityTrusted = trusted
        cameraStatus = camera
        updateActivity()
    }

    private func settingsChanged() {
        let updated = AppSettings.current()
        guard updated != settings else { return }
        let previous = settings
        settings = updated
        engine.settings = updated
        if updated.hotKeyCode != previous.hotKeyCode || updated.hotKeyModifiers != previous.hotKeyModifiers {
            registerHotKey()
        }
        if updated.cameraID != previous.cameraID {
            notifiedCameraChange = false
            updateActivity()
        }
        if updated.electronPanes != previous.electronPanes {
            worker.update(options: FocusWorker.Options(electronPanes: updated.electronPanes))
        }
        statusMenu?.refresh()
    }

    private func displaysChanged() {
        let current = Displays.current()
        guard current != displays else { return }
        displays = current
        engine.displays = current
        worker.update(displays: current)
        overlay.configure(displays: current)
        retrain(validate: false)
    }

    private func cameraStateChanged(_ state: CameraService.State) {
        cameraState = state
        switch state {
        case .running(let id, let name):
            cameraRetries = 0
            engine.log("Camera: \(name)")
            if let calibrated = profile.cameraID, calibrated != id, !profile.screens.isEmpty, !notifiedCameraChange {
                notifiedCameraChange = true
                Notifier.post(id: "camera", title: "Different camera", body: "SightShift was calibrated with another camera. Recalibrate so it knows how \(name) sees you.")
            }
        case .failed(let message):
            if cameraRetries == 0 { engine.log("Camera problem: \(message)") }
            if isCalibrating {
                calibration.abort(reason: "The camera stopped: \(message)")
            }
            // Cameras come back (a woken Mac, a busy camera freed up): retry a few times, backing
            // off. A reconnected camera also triggers a retry through `onDeviceConnected`.
            if cameraRetries < 5 {
                let delay = 3.0 * pow(2.0, Double(cameraRetries))
                cameraRetries += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self, case .failed = self.cameraState else { return }
                    self.updateActivity()
                }
            }
        case .stopped:
            break
        }
        statusMenu?.refresh()
    }

    var cameraName: String? {
        if case .running(_, let name) = cameraState { return name }
        return nil
    }

    var cameraProblem: String? {
        if case .failed(let message) = cameraState { return message }
        return nil
    }

    /// Connected screens that haven't been calibrated yet.
    var uncalibratedDisplays: [DisplayInfo] {
        displays.filter { profile.screens[$0.key] == nil }
    }

    /// Permissions granted and at least one screen calibrated.
    var isSetUp: Bool {
        accessibilityTrusted && cameraStatus == .authorized && !profile.screens.isEmpty
    }

    /// Why the camera is off, or nil when it's running.
    var cameraOffReason: String? {
        if cameraName != nil { return nil }
        if cameraStatus != .authorized { return "No camera access" }
        if let cameraProblem { return cameraProblem }
        if isPaused { return "Off while paused" }
        if isSuspended { return "Off while the Mac is locked or asleep" }
        if !hasModel { return "Off until calibrated" }
        if !accessibilityTrusted { return "Off until Accessibility is allowed" }
        return "Starting…"
    }

    var needsAttention: Bool {
        !accessibilityTrusted || cameraStatus != .authorized || profile.screens.isEmpty || !uncalibratedDisplays.isEmpty || cameraProblem != nil
    }

    var hotKeyDescription: String {
        KeyNames.describe(keyCode: settings.hotKeyCode, modifiers: settings.hotKeyModifiers)
    }

    // MARK: Model

    private func retrain(validate: Bool) {
        modelGeneration += 1
        let generation = modelGeneration
        let profile = profile
        let keys = displays.map(\.key)
        trainingQueue.async { [weak self] in
            let model = GazeModel.train(profile: profile, screenKeys: keys, validate: validate)
            Task { @MainActor in
                guard let self, generation == self.modelGeneration else { return }
                self.install(model, validated: validate)
            }
        }
    }

    private func install(_ model: GazeModel?, validated: Bool) {
        engine.setModel(model, keepTracking: !validated)
        hasModel = model != nil
        if validated || report == nil || model == nil { report = model?.report }
        updateActivity()
        notifyAboutUncalibratedScreens()
    }

    private func learn(_ sample: GazeSample, screen: String) {
        profile.addLearned(sample, screen: screen)
        if !retrainScheduled {
            retrainScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self else { return }
                self.retrainScheduled = false
                self.retrain(validate: false)
            }
        }
        if !saveScheduled {
            saveScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
                guard let self else { return }
                self.saveScheduled = false
                self.store.save(self.profile)
            }
        }
    }

    private func notifyAboutUncalibratedScreens() {
        guard !profile.screens.isEmpty, !isCalibrating else { return }
        for display in uncalibratedDisplays where !notifiedScreens.contains(display.key) {
            notifiedScreens.insert(display.key)
            Notifier.post(
                id: "calibrate-\(display.key)",
                title: "Calibrate \(display.name)",
                body: "SightShift can't switch to this screen until it's calibrated. Choose Calibrate from the menu bar icon."
            )
        }
        statusMenu?.refresh()
    }

    // MARK: Actions

    func togglePause() {
        isPaused.toggle()
        engine.log(isPaused ? "Paused" : "Resumed")
        updateActivity()
    }

    func startCalibration(only keys: [String]? = nil) {
        guard !isCalibrating else { return }
        guard cameraStatus == .authorized else {
            showOnboarding()
            return
        }
        let targets = keys.map { keys in displays.filter { keys.contains($0.key) } } ?? displays
        guard !targets.isEmpty else { return }
        isCalibrating = true
        updateActivity()
        presenter.rememberFrontmostApp()
        calibration.start(displays: targets, allDisplays: displays)
    }

    private func calibrationFinished(_ calibrations: [ScreenCalibration], requested: [DisplayInfo], run: Int) {
        for calibration in calibrations {
            profile.setCalibration(calibration)
            notifiedScreens.remove(calibration.screenKey)
        }
        if !calibrations.isEmpty, case .running(let id, _) = cameraState {
            profile.cameraID = id
            notifiedCameraChange = false
        }
        store.save(profile)

        modelGeneration += 1
        let generation = modelGeneration
        let profile = profile
        let keys = displays.map(\.key)
        trainingQueue.async { [weak self] in
            let model = GazeModel.train(profile: profile, screenKeys: keys, validate: true)
            Task { @MainActor in
                guard let self else { return }
                if generation == self.modelGeneration { self.install(model, validated: true) }
                let summary = self.summary(model: model, calibrations: calibrations, requested: requested)
                self.calibration.showResult(title: summary.title, lines: summary.lines, session: run)
            }
        }
    }

    private func summary(model: GazeModel?, calibrations: [ScreenCalibration], requested: [DisplayInfo]) -> (title: String, lines: [String]) {
        var lines: [String] = []
        let missed = requested.filter { display in !calibrations.contains { $0.screenKey == display.key } }
        if !missed.isEmpty {
            lines.append("Couldn't see your face well enough on \(missed.map(\.name).joined(separator: ", ")). More light usually helps.")
        }
        guard let model else {
            return ("Calibration didn't work", lines + ["SightShift needs to see your face while you follow the dot."])
        }
        let report = model.report
        if let accuracy = report.overallAccuracy {
            let perScreen = model.screenKeys.compactMap { key -> String? in
                guard let value = report.screenAccuracy[key] else { return nil }
                return "\(name(of: key)) \(Int((value * 100).rounded()))%"
            }
            lines.append("Screen accuracy \(Int((accuracy * 100).rounded()))%  ·  " + perScreen.joined(separator: "  ·  "))
            if let pair = report.closestPair, pair.distance < 3 {
                lines.append("\(name(of: pair.a)) and \(name(of: pair.b)) look alike from the camera. Turn your head naturally toward each one and recalibrate if switching feels unreliable.")
            }
        } else {
            lines.append("With one screen, SightShift focuses the window or split pane you look at.")
        }
        let remaining = uncalibratedDisplays
        if !remaining.isEmpty {
            lines.append("Still to calibrate: \(remaining.map(\.name).joined(separator: ", ")).")
        }
        let good = missed.isEmpty && (report.overallAccuracy ?? 1) >= 0.85
        return (good ? "You're all set" : "Calibration finished", lines)
    }

    private func name(of screenKey: String) -> String {
        displays.first { $0.key == screenKey }?.name ?? profile.screens[screenKey]?.screenName ?? "Screen"
    }

    func requestCamera() {
        if cameraStatus == .notDetermined {
            Permissions.requestCamera { [weak self] _ in self?.refreshPermissions() }
        } else {
            Permissions.openCameraSettings()
        }
    }

    func requestAccessibility() {
        // The system prompt adds SightShift to the list and offers to open it; after the first
        // time, go straight to System Settings.
        if UserDefaults.standard.bool(forKey: PrefKey.accessibilityPromptShown) {
            Permissions.openAccessibilitySettings()
        } else {
            UserDefaults.standard.set(true, forKey: PrefKey.accessibilityPromptShown)
            AX.requestTrust()
        }
    }

    func forgetLearnedClicks() {
        profile.forgetLearned()
        store.save(profile)
        retrain(validate: false)
    }

    func deleteCalibration() {
        let camera = profile.cameraID
        profile = CalibrationProfile(cameraID: camera)
        store.delete()
        notifiedScreens = []
        retrain(validate: true)
    }

    func finishOnboarding() {
        presenter.close(id: "onboarding")
    }

    private func registerHotKey() {
        hotKey?.invalidate()
        hotKey = HotKey(keyCode: settings.hotKeyCode, modifiers: settings.hotKeyModifiers) { [weak self] in
            self?.togglePause()
        }
        if hotKey == nil { engine.log("Couldn't register \(hotKeyDescription); another app may be using it") }
    }

    /// Lets the shortcut recorder receive the current shortcut instead of pausing.
    func setHotKeySuspended(_ suspended: Bool) {
        if suspended {
            hotKey?.invalidate()
            hotKey = nil
        } else {
            registerHotKey()
        }
    }

    // MARK: Windows

    func showOnboarding() {
        presenter.show(id: "onboarding", title: "Welcome to SightShift", content: OnboardingView(controller: self))
    }

    func showSettings() {
        presenter.show(id: "settings", title: "SightShift Settings", content: SettingsView(controller: self))
    }

    func showDiagnostics() {
        diagnosticsOpen = true
        status.isObserved = true
        updateActivity()
        presenter.show(id: "diagnostics", title: "SightShift Diagnostics", content: DiagnosticsView(controller: self, status: status)) { [weak self] in
            guard let self else { return }
            self.diagnosticsOpen = false
            self.status.isObserved = false
            self.updateActivity()
        }
    }

    func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(
                string: "Keyboard focus follows your gaze.\nFree and open source. Everything runs on this Mac.",
                attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
            ),
        ])
    }

    @objc func openSettingsFromMenu(_ sender: Any?) {
        showSettings()
    }
}

/// Opens SwiftUI content in ordinary windows (the app has no Dock icon or main window).
@MainActor
final class WindowPresenter: NSObject, NSWindowDelegate {
    private var windows: [String: NSWindow] = [:]
    private var closeHandlers: [String: () -> Void] = [:]
    private var previousApp: NSRunningApplication?
    private var activationObserver: NSObjectProtocol?

    override init() {
        super.init()
        rememberFrontmostApp()
        // Track the last app you used, so focus can go back there when SightShift is done.
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, app != .current else { return }
            MainActor.assumeIsolated { self?.previousApp = app }
        }
    }

    /// Remembers which app to return to before SightShift takes the foreground.
    func rememberFrontmostApp() {
        if let frontmost = NSWorkspace.shared.frontmostApplication, frontmost != .current {
            previousApp = frontmost
        }
    }

    /// When SightShift is active without a key window, keys one of its windows if any are open,
    /// and otherwise gives keyboard focus back to the app you were using.
    func handBackFocus() {
        guard NSApp.isActive, NSApp.keyWindow == nil else { return }
        if let window = windows.values.first(where: \.isVisible) {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let otherWindowOpen = NSApp.windows.contains { $0.isVisible && $0.level == .normal && $0.styleMask.contains(.titled) }
        guard !otherWindowOpen, let previousApp, !previousApp.isTerminated else { return }
        NSApp.yieldActivation(to: previousApp)
        previousApp.activate()
    }

    func show<Content: View>(id: String, title: String, content: Content, onClose: (() -> Void)? = nil) {
        rememberFrontmostApp()
        NSApp.activate()
        if let window = windows[id] {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingController(rootView: content)
        hosting.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: hosting)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier(id)
        window.delegate = self
        window.center()
        windows[id] = window
        closeHandlers[id] = onClose
        window.makeKeyAndOrderFront(nil)
    }

    func close(id: String) {
        windows[id]?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, let id = window.identifier?.rawValue else { return }
        windows[id] = nil
        closeHandlers.removeValue(forKey: id)?()
    }
}

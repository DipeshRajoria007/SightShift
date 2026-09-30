import Carbon.HIToolbox
import SightShiftCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var controller: AppController

    @AppStorage(PrefKey.cameraID) private var cameraID = ""
    @AppStorage(PrefKey.screenSwitchDelay) private var screenSwitchDelay = Defaults.screenSwitchDelay
    @AppStorage(PrefKey.headTurnThreshold) private var headTurnThreshold = Defaults.headTurnThreshold
    @AppStorage(PrefKey.movePointer) private var movePointer = true
    @AppStorage(PrefKey.sameScreenFocus) private var sameScreenFocus = true
    @AppStorage(PrefKey.paneDelay) private var paneDelay = Defaults.paneDelay
    @AppStorage(PrefKey.clickToFocusPanes) private var clickToFocusPanes = true
    @AppStorage(PrefKey.waitWhileTyping) private var waitWhileTyping = true
    @AppStorage(PrefKey.typingPause) private var typingPause = Defaults.typingPause
    @AppStorage(PrefKey.pointerPause) private var pointerPause = Defaults.pointerPause
    @AppStorage(PrefKey.learnFromClicks) private var learnFromClicks = true
    @AppStorage(PrefKey.showGazeDot) private var showGazeDot = false
    @AppStorage(PrefKey.electronPanes) private var electronPanes = false

    @State private var cameras = CameraService.availableDevices()
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginError: String?
    @State private var confirmDelete = false

    var body: some View {
        Form {
            Section {
                SliderRow(title: "Delay before switching", value: $screenSwitchDelay, range: 0.1...1.0, step: 0.05, label: milliseconds)
                SliderRow(title: "Head turn needed", value: $headTurnThreshold, range: 0.5...0.9, step: 0.05, label: percent)
                Toggle("Bring the pointer along", isOn: $movePointer)
            } header: {
                Text("Switching screens")
            } footer: {
                Text("Quick glances are ignored. Going back to a screen always needs a slightly bigger turn, so looking at a bezel doesn't flip focus back and forth.")
            }

            Section {
                Toggle("Focus the window or split pane I look at", isOn: $sameScreenFocus)
                SliderRow(title: "Delay", value: $paneDelay, range: 0.15...1.5, step: 0.05, label: milliseconds)
                    .disabled(!sameScreenFocus)
                Toggle("Click a terminal pane that won't take focus directly", isOn: $clickToFocusPanes)
                    .disabled(!sameScreenFocus)
                Toggle("Split panes in VS Code, Cursor and other Electron editors", isOn: $electronPanes)
                    .disabled(!sameScreenFocus)
            } header: {
                Text("Same screen")
            } footer: {
                Text("Pane focus works in iTerm2, Terminal, Ghostty, cmux, Xcode and JetBrains IDEs. Electron editors only reveal their panes when asked, and asking can switch them into screen reader mode; set editor.accessibilitySupport to \"off\" in their settings to prevent that.")
            }

            Section("Typing and mouse") {
                Toggle("Wait while I'm typing", isOn: $waitWhileTyping)
                SliderRow(title: "Typing pause", value: $typingPause, range: 0.5...6, step: 0.25, label: seconds)
                    .disabled(!waitWhileTyping)
                SliderRow(title: "Mouse rest", value: $pointerPause, range: 0.5...4, step: 0.25, label: seconds)
            }

            Section("Camera") {
                Picker("Camera", selection: $cameraID) {
                    Text("Built-in (automatic)").tag("")
                    ForEach(cameras) { camera in
                        Text(camera.name).tag(camera.id)
                    }
                }
                LabeledContent("Status", value: controller.cameraName.map { "Using \($0)" } ?? controller.cameraOffReason ?? "")
            }

            Section {
                Toggle("Learn from my clicks", isOn: $learnFromClicks)
                LabeledContent("Clicks learned") {
                    HStack {
                        Text("\(controller.profile.learnedSampleCount)")
                            .monospacedDigit()
                        Button("Forget") { controller.forgetLearnedClicks() }
                            .disabled(controller.profile.learnedSampleCount == 0)
                    }
                }
            } header: {
                Text("Learning")
            } footer: {
                Text("You look where you click, so each click teaches SightShift a little more — including when you sit closer, farther away or off to one side.")
            }

            Section("Calibration") {
                ForEach(controller.displays) { display in
                    LabeledContent {
                        Button("Calibrate") { controller.startCalibration(only: [display.key]) }
                            .disabled(controller.isCalibrating)
                    } label: {
                        Text(display.name)
                        Text(calibrationDescription(for: display))
                    }
                }
                HStack {
                    Button("Calibrate All Screens") { controller.startCalibration() }
                        .disabled(controller.isCalibrating)
                    Spacer()
                    Button("Delete Calibration…", role: .destructive) { confirmDelete = true }
                        .disabled(controller.profile.screens.isEmpty)
                }
            }

            Section("Extras") {
                Toggle("Show gaze dot", isOn: $showGazeDot)
                LabeledContent("Pause / resume shortcut") { ShortcutRecorder(controller: controller) }
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            try LoginItem.set(enabled)
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = LoginItem.isEnabled
                        }
                    }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 700)
        .confirmationDialog("Delete all calibration data?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { controller.deleteCalibration() }
        } message: {
            Text("SightShift stops switching until you calibrate again.")
        }
    }

    private func calibrationDescription(for display: DisplayInfo) -> String {
        guard let calibration = controller.profile.screens[display.key] else { return "Not calibrated" }
        var text = "Calibrated " + calibration.calibratedAt.formatted(.relative(presentation: .named))
        if let accuracy = controller.report?.screenAccuracy[display.key] {
            text += " · \(Int((accuracy * 100).rounded()))% accurate"
        }
        return text
    }

    private func milliseconds(_ value: Double) -> String { "\(Int((value * 1000).rounded())) ms" }
    private func seconds(_ value: Double) -> String { String(format: "%.2g s", value) }
    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
}

private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let label: (Double) -> String

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                Slider(value: $value, in: range, step: step)
                    .frame(width: 180)
                Text(label(value))
                    .monospacedDigit()
                    .frame(width: 56, alignment: .trailing)
            }
        }
    }
}

/// Records a new system-wide shortcut for pausing SightShift.
struct ShortcutRecorder: View {
    let controller: AppController
    @AppStorage(PrefKey.hotKeyCode) private var keyCode = Defaults.hotKeyCode
    @AppStorage(PrefKey.hotKeyModifiers) private var modifiers = Defaults.hotKeyModifiers
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Button(recording ? "Type a shortcut…" : KeyNames.describe(keyCode: UInt32(keyCode), modifiers: UInt32(modifiers))) {
                recording ? stop() : start()
            }
            .frame(minWidth: 110)
            if !recording, keyCode != Defaults.hotKeyCode || modifiers != Defaults.hotKeyModifiers {
                Button("Reset") {
                    keyCode = Defaults.hotKeyCode
                    modifiers = Defaults.hotKeyModifiers
                }
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        controller.setHotKeySuspended(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stop()
                return nil
            }
            let carbon = KeyNames.carbonModifiers(from: event.modifierFlags)
            // A global shortcut swallows its keys everywhere, so it needs ⌃ or ⌥ to stay clear
            // of typing and of everyday ⌘ shortcuts.
            guard KeyNames.isAcceptableGlobalShortcut(modifiers: carbon) else {
                NSSound.beep()
                return nil
            }
            keyCode = Int(event.keyCode)
            modifiers = Int(carbon)
            stop()
            return nil
        }
    }

    private func stop() {
        guard recording else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        controller.setHotKeySuspended(false)
    }
}

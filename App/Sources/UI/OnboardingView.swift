import SwiftUI

struct OnboardingView: View {
    @ObservedObject var controller: AppController

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to SightShift")
                        .font(.title.bold())
                    Text("Look at a screen, window or split pane and start typing. Keyboard focus is already there.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            StepRow(
                index: 1,
                title: "Allow the camera",
                detail: "SightShift estimates which way your head is turned. Frames are analysed in memory on this Mac and thrown away.",
                done: controller.cameraStatus == .authorized
            ) {
                Button(controller.cameraStatus == .notDetermined ? "Allow Camera" : "Open Camera Settings") {
                    controller.requestCamera()
                }
            }

            StepRow(
                index: 2,
                title: "Allow Accessibility",
                detail: "Lets SightShift move keyboard focus between windows and notice when you're typing. Turn on SightShift in the list that opens.",
                done: controller.accessibilityTrusted
            ) {
                Button("Open Accessibility Settings") { controller.requestAccessibility() }
            }

            StepRow(
                index: 3,
                title: "Calibrate",
                detail: "Follow a dot around each screen, about 20 seconds per screen. Face each screen the way you normally would.",
                done: !controller.profile.screens.isEmpty && controller.uncalibratedDisplays.isEmpty
            ) {
                Button(controller.profile.screens.isEmpty ? "Start Calibration" : "Calibrate New Screens") {
                    if controller.profile.screens.isEmpty {
                        controller.startCalibration()
                    } else {
                        controller.startCalibration(only: controller.uncalibratedDisplays.map(\.key))
                    }
                }
                .disabled(controller.cameraStatus != .authorized || controller.isCalibrating)
            }

            Divider()

            Label("No cloud, no account, no analytics. SightShift never records or uploads anything.", systemImage: "lock.shield")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Text("Pause any time with \(controller.hotKeyDescription).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") { controller.finishOnboarding() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 580)
    }
}

private struct StepRow<Action: View>: View {
    let index: Int
    let title: String
    let detail: String
    let done: Bool
    @ViewBuilder var action: () -> Action

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(done ? Color.green : Color.accentColor.opacity(0.15))
                    .frame(width: 28, height: 28)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(index)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if !done {
                action()
            }
        }
    }
}

import SightShiftCore
import SwiftUI

/// Live view of what SightShift sees and decides, for tuning and troubleshooting.
struct DiagnosticsView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var status: EngineStatus

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                GroupBox("Camera") {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                        row("Camera", controller.cameraName ?? controller.cameraProblem ?? "Off")
                        row("Face", status.faceVisible ? "Visible" : "Not visible")
                        row("Frame rate", String(format: "%.1f fps", status.framesPerSecond))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                GroupBox("Decision") {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                        row("Looking at", status.gazeScreenName ?? "—")
                        row("Closest screen", status.nearestScreenName ?? "—")
                        row("Aimed at a screen", status.onScreen ? "Yes" : "No")
                        row("Distance / limit", String(format: "%.2f / %.2f", status.gateDistance, status.gateRadius))
                        row("Keyboard focus", [status.focusScreenName, status.focusAppName].compactMap { $0 }.joined(separator: " · "))
                        row("Split panes", status.paneCount > 0 ? "\(status.paneCount)" : "—")
                        row("Holding", status.waitingFor ?? "—")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                GroupBox("Distance to each screen") {
                    VStack(alignment: .leading, spacing: 4) {
                        if status.scores.isEmpty {
                            Text("Not calibrated").foregroundStyle(.secondary)
                        }
                        ForEach(status.scores) { score in
                            HStack {
                                Text(score.name).lineLimit(1)
                                Spacer()
                                Text(String(format: "%.2f", score.distance)).monospacedDigit()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                GroupBox("Features") {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                        ForEach(Feature.allCases, id: \.self) { feature in
                            GridRow {
                                Text(feature.label).foregroundStyle(.secondary)
                                Text(status.features.count == Feature.count ? String(format: "%+.3f", status.features[feature.rawValue]) : "—")
                                    .monospacedDigit()
                            }
                        }
                    }
                    .font(.system(size: 11))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(width: 300)

            VStack(alignment: .leading, spacing: 12) {
                GroupBox("Head pose (yaw × pitch)") {
                    PoseMap(profile: controller.profile, displays: controller.displays, current: status.features)
                        .frame(height: 260)
                }
                GroupBox("Activity") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(status.log.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(size: 11, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 250)
                }
            }
            .frame(width: 400)
        }
        .padding(16)
    }

    private func row(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value.isEmpty ? "—" : value).lineLimit(1)
        }
    }
}

/// Calibration samples for each screen, with the current pose on top.
private struct PoseMap: View {
    let profile: CalibrationProfile
    let displays: [DisplayInfo]
    let current: [Double]

    private static let colors: [Color] = [.blue, .orange, .green, .purple, .pink, .teal]

    var body: some View {
        let clouds = displays.enumerated().compactMap { index, display -> (name: String, color: Color, points: [CGPoint])? in
            guard let samples = profile.screens[display.key]?.samples, !samples.isEmpty else { return nil }
            let points = samples.enumerated().filter { $0.offset % 3 == 0 }.map { point(from: $0.element.features) }
            return (display.name, Self.colors[index % Self.colors.count], points)
        }
        let currentPoint = current.count == Feature.count ? point(from: current) : nil
        let all = clouds.flatMap(\.points) + (currentPoint.map { [$0] } ?? [])
        let bounds = Self.bounds(of: all)

        VStack(alignment: .leading, spacing: 6) {
            Canvas { context, size in
                func place(_ p: CGPoint) -> CGPoint {
                    CGPoint(
                        x: (p.x - bounds.minX) / bounds.width * size.width,
                        y: size.height - (p.y - bounds.minY) / bounds.height * size.height
                    )
                }
                for cloud in clouds {
                    for p in cloud.points {
                        let at = place(p)
                        context.fill(Path(ellipseIn: CGRect(x: at.x - 2, y: at.y - 2, width: 4, height: 4)), with: .color(cloud.color.opacity(0.5)))
                    }
                }
                if let currentPoint {
                    let at = place(currentPoint)
                    context.stroke(Path(ellipseIn: CGRect(x: at.x - 7, y: at.y - 7, width: 14, height: 14)), with: .color(.primary), lineWidth: 2)
                }
            }
            .background(Color.secondary.opacity(0.06))
            HStack(spacing: 12) {
                ForEach(Array(clouds.enumerated()), id: \.offset) { _, cloud in
                    Label(cloud.name, systemImage: "circle.fill")
                        .foregroundStyle(cloud.color)
                        .font(.caption)
                        .lineLimit(1)
                }
            }
        }
    }

    private func point(from features: [Double]) -> CGPoint {
        CGPoint(x: features[Feature.yaw.rawValue], y: features[Feature.pitch.rawValue])
    }

    private static func bounds(of points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return CGRect(x: -1, y: -1, width: 2, height: 2) }
        var rect = CGRect(origin: first, size: .zero)
        for p in points { rect = rect.union(CGRect(origin: p, size: .zero)) }
        let padX = max(rect.width * 0.1, 0.05)
        let padY = max(rect.height * 0.1, 0.05)
        return rect.insetBy(dx: -padX, dy: -padY)
    }
}

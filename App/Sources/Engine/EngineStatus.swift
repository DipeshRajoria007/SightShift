import Foundation
import SightShiftCore

/// Live numbers for the diagnostics window and the menu's status line.
@MainActor
final class EngineStatus: ObservableObject {
    struct ScreenScore: Identifiable, Equatable {
        var id: String { key }
        let key: String
        let name: String
        let distance: Double
    }

    @Published var faceVisible = false
    @Published var framesPerSecond = 0.0
    @Published var features: [Double] = []
    @Published var gazeScreenName: String?
    @Published var nearestScreenName: String?
    @Published var focusScreenName: String?
    @Published var focusAppName: String?
    @Published var scores: [ScreenScore] = []
    @Published var gateDistance = 0.0
    @Published var gateRadius = 0.0
    @Published var onScreen = false
    @Published var gazePoint: ScreenPoint?
    @Published var waitingFor: String?
    @Published var paneCount = 0
    @Published var log: [String] = []

    /// Detailed values are only published while someone is looking at them.
    var isObserved = false

    func append(_ line: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        log.insert("\(formatter.string(from: Date()))  \(line)", at: 0)
        if log.count > 40 { log.removeLast(log.count - 40) }
    }
}

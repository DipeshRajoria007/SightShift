import Foundation
import SightShiftCore

/// Saves the calibration profile as JSON in Application Support. It holds numbers describing
/// head poses, never images.
final class ProfileStore {
    private let url: URL
    private let queue = DispatchQueue(label: "app.sightshift.store", qos: .utility)

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let directory = base.appendingPathComponent("SightShift", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("profile.json")
    }

    var fileURL: URL { url }

    func load() -> CalibrationProfile? {
        guard let data = try? Data(contentsOf: url),
              let profile = try? JSONDecoder().decode(CalibrationProfile.self, from: data),
              profile.isCompatible else { return nil }
        return profile
    }

    func save(_ profile: CalibrationProfile) {
        queue.async { [url] in Self.write(profile, to: url) }
    }

    /// Writes before returning, for when the app is about to quit.
    func saveNow(_ profile: CalibrationProfile) {
        queue.sync { Self.write(profile, to: url) }
    }

    private static func write(_ profile: CalibrationProfile, to url: URL) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func delete() {
        queue.async { [url] in try? FileManager.default.removeItem(at: url) }
    }
}

import Foundation

/// One observation of the face while the user looked at a known point on a screen.
public struct GazeSample: Codable, Equatable, Sendable {
    public var features: [Double]
    /// Horizontal position on the screen, 0 at the left edge and 1 at the right.
    public var u: Double
    /// Vertical position on the screen, 0 at the top edge and 1 at the bottom.
    public var v: Double
    /// Index of the calibration dot, or `GazeSample.learned` for samples learned from clicks.
    public var point: Int
    /// Seconds since 2001-01-01, like `Date.timeIntervalSinceReferenceDate`.
    public var time: Double

    public static let learned = -1

    public init(features: [Double], u: Double, v: Double, point: Int, time: Double) {
        self.features = features
        self.u = u
        self.v = v
        self.point = point
        self.time = time
    }
}

public struct ScreenCalibration: Codable, Equatable, Sendable {
    public var screenKey: String
    public var screenName: String
    public var calibratedAt: Date
    public var samples: [GazeSample]

    public init(screenKey: String, screenName: String, calibratedAt: Date, samples: [GazeSample]) {
        self.screenKey = screenKey
        self.screenName = screenName
        self.calibratedAt = calibratedAt
        self.samples = samples
    }
}

/// Everything SightShift has learned about how your head moves when you look at each screen.
/// Stored as plain numbers; no images ever leave the camera pipeline.
public struct CalibrationProfile: Codable, Equatable, Sendable {
    public static let formatVersion = 1
    public static let maxLearnedPerScreen = 240

    public var version: Int
    public var featureCount: Int
    public var cameraID: String?
    public var screens: [String: ScreenCalibration]
    public var learned: [String: [GazeSample]]

    public init(cameraID: String? = nil) {
        self.version = Self.formatVersion
        self.featureCount = Feature.count
        self.cameraID = cameraID
        self.screens = [:]
        self.learned = [:]
    }

    /// Whether this profile was written by a compatible version of the feature extractor.
    public var isCompatible: Bool {
        version == Self.formatVersion && featureCount == Feature.count
    }

    public var learnedSampleCount: Int {
        learned.values.reduce(0) { $0 + $1.count }
    }

    public mutating func setCalibration(_ calibration: ScreenCalibration) {
        screens[calibration.screenKey] = calibration
        // Clicks learned before a recalibration describe the old setup.
        learned[calibration.screenKey] = nil
    }

    public mutating func addLearned(_ sample: GazeSample, screen: String) {
        var list = learned[screen] ?? []
        list.append(sample)
        if list.count > Self.maxLearnedPerScreen {
            list.removeFirst(list.count - Self.maxLearnedPerScreen)
        }
        learned[screen] = list
    }

    public mutating func forgetLearned() {
        learned = [:]
    }
}

public enum SampleCleaner {
    /// Drops frames that disagree wildly with the other frames recorded for the same dot:
    /// blinks, a glance away, or a detector glitch. Learned samples pass through untouched.
    public static func clean(_ samples: [GazeSample]) -> [GazeSample] {
        let groups = Dictionary(grouping: samples.indices, by: { samples[$0].point })
        var keep = [Bool](repeating: true, count: samples.count)
        for (point, indices) in groups where point != GazeSample.learned && indices.count >= 5 {
            for feature in Feature.allCases {
                let values = indices.map { samples[$0].features[feature.rawValue] }
                let median = Stats.median(values)
                let spread = max(Stats.robustSpread(values), feature.minimumSpread * 0.5)
                for (offset, index) in indices.enumerated() where abs(values[offset] - median) > 4 * spread {
                    keep[index] = false
                }
            }
        }
        return samples.indices.filter { keep[$0] }.map { samples[$0] }
    }
}

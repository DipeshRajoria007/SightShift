import Foundation

public struct TrainingReport: Sendable {
    public var screenKeys: [String] = []
    public var sampleCounts: [String: Int] = [:]
    /// Share of held-out calibration frames assigned to the right screen, when each dot is left
    /// out of training in turn (1 = perfect). Absent for a single screen.
    public var screenAccuracy: [String: Double] = [:]
    /// Cross-validated error of the on-screen position, as a fraction of the screen size.
    public var pointError: [String: Double] = [:]
    /// The two screens the camera finds hardest to tell apart, and how far apart they are
    /// in whitened units (below about 3 means switching between them will be unreliable).
    public var closestPair: (a: String, b: String, distance: Double)?

    public init() {}

    public var overallAccuracy: Double? {
        guard !screenAccuracy.isEmpty else { return nil }
        return screenAccuracy.values.reduce(0, +) / Double(screenAccuracy.count)
    }
}

public struct GazeEstimate: Sendable {
    public let evaluation: ScreenClassifier.Evaluation
    /// The screen you're looking at after hysteresis, or `nil` when the pose isn't aimed at any screen.
    public let screen: String?
    public let nearest: String
    /// Where on `screen` (or the nearest screen, when `screen` is nil) you seem to be looking.
    public let point: ScreenPoint?
}

/// The trained gaze model: which screen, and where on it.
public struct GazeModel: Sendable {
    public struct Options: Sendable {
        /// A click is one frame against a calibration dot's dozen, so it counts a little extra.
        public var learnedSampleWeight = 2.0
        public var classifier = ScreenClassifier.Options()
        /// How far past a screen's edge (as a fraction of its size) the estimated point may land
        /// before the pose counts as looking off-screen.
        public var offScreenMargin = 0.25

        public init() {}
    }

    public let screenKeys: [String]
    public let classifier: ScreenClassifier
    public let regressors: [String: PointRegressor]
    public let report: TrainingReport
    public let options: Options

    /// Trains on the calibrated screens among `screenKeys`, in that order.
    public static func train(
        profile: CalibrationProfile,
        screenKeys requested: [String],
        options: Options = Options(),
        validate: Bool = true
    ) -> GazeModel? {
        guard profile.isCompatible else { return nil }
        let keys = requested.filter { profile.screens[$0] != nil }
        guard !keys.isEmpty else { return nil }

        var features: [[Double]] = []
        var labels: [Int] = []
        var weights: [Double] = []
        var groups: [Int] = []
        var targets: [ScreenPoint] = []
        var report = TrainingReport()
        report.screenKeys = keys

        for (label, key) in keys.enumerated() {
            let calibration = SampleCleaner.clean(profile.screens[key]?.samples ?? [])
                .filter { $0.features.count == Feature.count }
            let learned = (profile.learned[key] ?? []).filter { $0.features.count == Feature.count }
            for sample in calibration {
                features.append(sample.features)
                labels.append(label)
                weights.append(1)
                groups.append(sample.point)
                targets.append(ScreenPoint(u: sample.u, v: sample.v))
            }
            for (index, sample) in learned.enumerated() {
                features.append(sample.features)
                labels.append(label)
                weights.append(options.learnedSampleWeight)
                groups.append(1000 + index % 10)
                targets.append(ScreenPoint(u: sample.u, v: sample.v))
            }
            report.sampleCounts[key] = calibration.count + learned.count
        }

        guard let classifier = ScreenClassifier(
            features: features, labels: labels, weights: weights, classCount: keys.count, options: options.classifier
        ) else { return nil }

        var regressors: [String: PointRegressor] = [:]
        for (label, key) in keys.enumerated() {
            let rows = labels.indices.filter { labels[$0] == label }
            if let regressor = PointRegressor(
                features: rows.map { features[$0] },
                targets: rows.map { targets[$0] },
                weights: rows.map { weights[$0] },
                groups: rows.map { groups[$0] }
            ) {
                regressors[key] = regressor
                report.pointError[key] = regressor.validationError
            }
        }

        if let pair = classifier.closestPair() {
            report.closestPair = (keys[pair.a], keys[pair.b], pair.distance)
        }
        if validate, keys.count > 1 {
            report.screenAccuracy = leaveOneDotOutAccuracy(
                features: features, labels: labels, weights: weights, groups: groups, keys: keys, options: options
            )
        }

        return GazeModel(screenKeys: keys, classifier: classifier, regressors: regressors, report: report, options: options)
    }

    public func estimate(_ x: [Double], current: String?, threshold: Double, hysteresis: Double) -> GazeEstimate {
        let evaluation = classifier.evaluate(x)
        let currentIndex = current.flatMap { screenKeys.firstIndex(of: $0) }
        var screen = classifier.decide(evaluation, current: currentIndex, threshold: threshold, hysteresis: hysteresis)
            .map { screenKeys[$0] }
        let nearest = screenKeys[evaluation.nearest]
        let point = regressors[screen ?? nearest]?.predict(x)
        if screen != nil, let point, !point.isWithin(margin: options.offScreenMargin) {
            // Aimed well past the edge of the screen: probably a phone or a notebook below it.
            screen = nil
        }
        return GazeEstimate(evaluation: evaluation, screen: screen, nearest: nearest, point: point)
    }

    public func point(on screen: String, features x: [Double]) -> ScreenPoint? {
        regressors[screen]?.predict(x)
    }

    private static func leaveOneDotOutAccuracy(
        features: [[Double]],
        labels: [Int],
        weights: [Double],
        groups: [Int],
        keys: [String],
        options: Options
    ) -> [String: Double] {
        var correct = [Double](repeating: 0, count: keys.count)
        var total = [Double](repeating: 0, count: keys.count)
        for label in keys.indices {
            let dots = Set(labels.indices.filter { labels[$0] == label && groups[$0] >= 0 && groups[$0] < 1000 }.map { groups[$0] })
            for dot in dots {
                let heldOut = labels.indices.filter { labels[$0] == label && groups[$0] == dot }
                let heldOutSet = Set(heldOut)
                let train = labels.indices.filter { !heldOutSet.contains($0) }
                guard let classifier = ScreenClassifier(
                    features: train.map { features[$0] },
                    labels: train.map { labels[$0] },
                    weights: train.map { weights[$0] },
                    classCount: keys.count,
                    options: options.classifier
                ) else { continue }
                for i in heldOut {
                    total[label] += 1
                    if classifier.evaluate(features[i]).nearest == label { correct[label] += 1 }
                }
            }
        }
        var accuracy: [String: Double] = [:]
        for (label, key) in keys.enumerated() where total[label] > 0 {
            accuracy[key] = correct[label] / total[label]
        }
        return accuracy
    }
}

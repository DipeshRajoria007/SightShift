import Foundation

/// Decides which screen a head pose belongs to.
///
/// Features are whitened with the pooled within-screen covariance (the LDA metric), so directions
/// that vary a lot while you look around a single screen count for less than directions that
/// separate one screen from another. Each screen is then represented by the centre of its
/// calibration samples, and switching is judged by how far you've turned along the line from the
/// current screen's centre toward another's.
public struct ScreenClassifier: Sendable {
    public struct Options: Sendable {
        /// How strongly the pooled covariance is pulled toward its diagonal (0 = not at all).
        public var shrinkage = 0.2
        /// Extra caution for features that describe where you sit rather than where you look, so
        /// leaning back or shifting in your chair doesn't read as a head turn.
        public var positionSpreadMultiplier = 2.0
        /// Poses further than this quantile of the training spread, times `gateScale`, from every
        /// screen and from the paths between screens are treated as "not looking at a screen".
        public var gateQuantile = 0.95
        public var gateScale = 1.75
        public var minimumGateRadius = 2.5

        public init() {}
    }

    public struct Evaluation: Sendable, Equatable {
        /// The pose in whitened units.
        public let point: [Double]
        /// Distance to each screen's centre, in whitened units.
        public let distances: [Double]
        public let nearest: Int
        /// Distance to the closest screen centre or path between two centres.
        public let gateDistance: Double
        public let isOnScreen: Bool
    }

    public let classCount: Int
    public let centroids: [[Double]]
    public let gateRadius: Double
    private let center: [Double]
    private let scale: [Double]
    private let whitening: Matrix

    /// - Parameters:
    ///   - features: one row per sample.
    ///   - labels: screen index for each row, in `0..<classCount`.
    ///   - minimumSpread: per-feature noise floor; defaults to `Feature.minimumSpread`.
    public init?(
        features: [[Double]],
        labels: [Int],
        weights: [Double]? = nil,
        classCount: Int,
        minimumSpread: [Double]? = nil,
        options: Options = Options()
    ) {
        guard classCount >= 1, !features.isEmpty, features.count == labels.count else { return nil }
        let d = features[0].count
        guard d > 0, features.allSatisfy({ $0.count == d }),
              labels.allSatisfy({ (0..<classCount).contains($0) }) else { return nil }
        let weights = weights ?? Array(repeating: 1, count: features.count)
        guard weights.count == features.count else { return nil }

        var classWeight = [Double](repeating: 0, count: classCount)
        for (label, w) in zip(labels, weights) { classWeight[label] += w }
        guard classWeight.allSatisfy({ $0 > 0 }) else { return nil }

        let floors = minimumSpread ?? Self.defaultMinimumSpread(count: d, positionMultiplier: options.positionSpreadMultiplier)
        guard floors.count == d else { return nil }

        let center = Stats.weightedMean(features, weights: weights)
        let spread = Stats.weightedStandardDeviation(features, weights: weights, center: center)
        let scale = zip(spread, floors).map { max($0, $1) }
        let scaled = features.map { row in (0..<d).map { (row[$0] - center[$0]) / scale[$0] } }

        var means = [[Double]](repeating: [Double](repeating: 0, count: d), count: classCount)
        for i in scaled.indices {
            for j in 0..<d { means[labels[i]][j] += weights[i] * scaled[i][j] }
        }
        for k in 0..<classCount {
            for j in 0..<d { means[k][j] /= classWeight[k] }
        }

        var covariance = Matrix(rows: d, cols: d)
        var total = 0.0
        for i in scaled.indices {
            let mean = means[labels[i]]
            for a in 0..<d {
                let da = scaled[i][a] - mean[a]
                for b in a..<d { covariance[a, b] += weights[i] * da * (scaled[i][b] - mean[b]) }
            }
            total += weights[i]
        }
        for a in 0..<d {
            for b in a..<d {
                covariance[a, b] /= total
                covariance[b, a] = covariance[a, b]
            }
        }
        for a in 0..<d {
            let floor = floors[a] / scale[a]
            covariance[a, a] = max(covariance[a, a], floor * floor)
        }
        for a in 0..<d {
            for b in 0..<d where a != b { covariance[a, b] *= 1 - options.shrinkage }
        }
        guard let cholesky = covariance.cholesky() else { return nil }
        let whitening = cholesky.lowerTriangularInverse()
        let centroids = means.map { whitening * $0 }
        let ownDistances = features.indices.map { i in
            Vec.distance(Self.whiten(features[i], center: center, scale: scale, whitening: whitening), centroids[labels[i]])
        }

        self.classCount = classCount
        self.center = center
        self.scale = scale
        self.whitening = whitening
        self.centroids = centroids
        self.gateRadius = max(options.minimumGateRadius, Stats.quantile(ownDistances, options.gateQuantile) * options.gateScale)
    }

    public static func defaultMinimumSpread(count: Int, positionMultiplier: Double) -> [Double] {
        (0..<count).map { index in
            guard let feature = Feature(rawValue: index), count == Feature.count else { return 1e-3 }
            return feature.describesPosition ? feature.minimumSpread * positionMultiplier : feature.minimumSpread
        }
    }

    public func whiten(_ x: [Double]) -> [Double] {
        Self.whiten(x, center: center, scale: scale, whitening: whitening)
    }

    private static func whiten(_ x: [Double], center: [Double], scale: [Double], whitening: Matrix) -> [Double] {
        whitening * (0..<center.count).map { (x[$0] - center[$0]) / scale[$0] }
    }

    public func evaluate(_ x: [Double]) -> Evaluation {
        let z = whiten(x)
        let distances = centroids.map { Vec.distance(z, $0) }
        let nearest = distances.indices.min(by: { distances[$0] < distances[$1] }) ?? 0
        var gate = distances[nearest]
        for a in 0..<classCount {
            for b in (a + 1)..<classCount {
                gate = min(gate, Vec.distanceToSegment(z, centroids[a], centroids[b]))
            }
        }
        return Evaluation(point: z, distances: distances, nearest: nearest, gateDistance: gate, isOnScreen: gate <= gateRadius)
    }

    /// How far the pose has travelled from screen `a`'s centre toward screen `b`'s:
    /// 0 when facing `a`, 1 when facing `b`.
    public func progress(of evaluation: Evaluation, from a: Int, toward b: Int) -> Double {
        let ab = Vec.subtract(centroids[b], centroids[a])
        let lengthSquared = Vec.dot(ab, ab)
        guard lengthSquared > 1e-9 else { return 0 }
        return Vec.dot(Vec.subtract(evaluation.point, centroids[a]), ab) / lengthSquared
    }

    /// The screen the user is looking at, given the one they were looking at before.
    ///
    /// - Parameters:
    ///   - threshold: fraction of the way toward another screen you must turn before it wins.
    ///     Clamped to at least one half so two screens can never both claim the same pose.
    ///   - hysteresis: extra turn required on top of `threshold`; it also makes going back
    ///     need a slightly bigger turn, so looking at a bezel doesn't ping-pong.
    /// - Returns: `nil` when the pose is far from every screen (a phone, the ceiling, a window).
    public func decide(_ evaluation: Evaluation, current: Int?, threshold: Double, hysteresis: Double) -> Int? {
        guard evaluation.isOnScreen else { return nil }
        guard let current, current >= 0, current < classCount else { return evaluation.nearest }
        let required = max(0.5, threshold) + max(0, hysteresis)
        var best: Int?
        for candidate in 0..<classCount where candidate != current {
            guard progress(of: evaluation, from: current, toward: candidate) >= required else { continue }
            if best == nil || evaluation.distances[candidate] < evaluation.distances[best!] { best = candidate }
        }
        return best ?? current
    }

    /// Closest pair of screen centres in whitened units. Small values mean the camera can barely
    /// tell those screens apart.
    public func closestPair() -> (a: Int, b: Int, distance: Double)? {
        var best: (a: Int, b: Int, distance: Double)?
        for a in 0..<classCount {
            for b in (a + 1)..<classCount {
                let d = Vec.distance(centroids[a], centroids[b])
                if best == nil || d < best!.distance { best = (a, b, d) }
            }
        }
        return best
    }
}

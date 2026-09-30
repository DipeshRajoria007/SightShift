import Foundation

/// Estimates where on one screen you're looking, from the face features.
///
/// A ridge regression on standardized features. The regularization strength is picked by
/// cross-validation that leaves out one calibration dot at a time, so the model is judged on
/// positions it hasn't seen rather than on frames it memorised.
public struct PointRegressor: Sendable {
    public static let defaultAlphas: [Double] = [0.003, 0.01, 0.03, 0.1, 0.3, 1.0]

    public let alpha: Double
    /// Cross-validated root-mean-square error, as a fraction of the screen size.
    /// `nil` when there weren't enough distinct dots to validate.
    public let validationError: Double?
    private let center: [Double]
    private let scale: [Double]
    private let coefficientsU: [Double]
    private let coefficientsV: [Double]

    /// - Parameters:
    ///   - groups: samples sharing a group are left out together during cross-validation
    ///     (normally the calibration dot index).
    public init?(
        features: [[Double]],
        targets: [ScreenPoint],
        weights: [Double]? = nil,
        groups: [Int]? = nil,
        minimumSpread: [Double]? = nil,
        alphas: [Double] = PointRegressor.defaultAlphas
    ) {
        let n = features.count
        guard n >= 3, targets.count == n, let d = features.first?.count, d > 0,
              features.allSatisfy({ $0.count == d }) else { return nil }
        let weights = weights ?? Array(repeating: 1, count: n)
        let groups = groups ?? (0..<n).map { $0 % 10 }
        guard weights.count == n, groups.count == n else { return nil }

        let floors = minimumSpread ?? ScreenClassifier.defaultMinimumSpread(count: d, positionMultiplier: 1)
        let center = Stats.weightedMean(features, weights: weights)
        let spread = Stats.weightedStandardDeviation(features, weights: weights, center: center)
        let scale = zip(spread, floors).map { max($0, $1) }
        let design = features.map { row in [1.0] + (0..<d).map { (row[$0] - center[$0]) / scale[$0] } }
        let allRows = Array(0..<n)

        let distinctGroups = Array(Set(groups)).sorted()
        var chosenAlpha = 0.1
        var bestError: Double?
        if distinctGroups.count >= 3 {
            for alpha in alphas {
                var squaredError = 0.0
                var total = 0.0
                var failed = false
                for group in distinctGroups {
                    let train = allRows.filter { groups[$0] != group }
                    guard let fit = Self.fit(design: design, targets: targets, weights: weights, rows: train, alpha: alpha) else {
                        failed = true
                        break
                    }
                    for i in allRows where groups[i] == group {
                        let du = Vec.dot(fit.u, design[i]) - targets[i].u
                        let dv = Vec.dot(fit.v, design[i]) - targets[i].v
                        squaredError += weights[i] * (du * du + dv * dv)
                        total += weights[i]
                    }
                }
                guard !failed, total > 0 else { continue }
                let rms = (squaredError / total).squareRoot()
                if bestError == nil || rms < bestError! {
                    bestError = rms
                    chosenAlpha = alpha
                }
            }
        }

        guard let fit = Self.fit(design: design, targets: targets, weights: weights, rows: allRows, alpha: chosenAlpha) else {
            return nil
        }
        self.alpha = chosenAlpha
        self.validationError = bestError
        self.center = center
        self.scale = scale
        self.coefficientsU = fit.u
        self.coefficientsV = fit.v
    }

    public func predict(_ x: [Double]) -> ScreenPoint {
        let row = [1.0] + (0..<center.count).map { (x[$0] - center[$0]) / scale[$0] }
        return ScreenPoint(u: Vec.dot(coefficientsU, row), v: Vec.dot(coefficientsV, row))
    }

    private static func fit(
        design: [[Double]],
        targets: [ScreenPoint],
        weights: [Double],
        rows: [Int],
        alpha: Double
    ) -> (u: [Double], v: [Double])? {
        let p = design[0].count
        var normal = Matrix(rows: p, cols: p)
        var rhsU = [Double](repeating: 0, count: p)
        var rhsV = [Double](repeating: 0, count: p)
        var total = 0.0
        for i in rows {
            let x = design[i]
            let w = weights[i]
            for r in 0..<p {
                rhsU[r] += w * x[r] * targets[i].u
                rhsV[r] += w * x[r] * targets[i].v
                for c in r..<p { normal[r, c] += w * x[r] * x[c] }
            }
            total += w
        }
        guard total > 0 else { return nil }
        for r in 0..<p {
            for c in r..<p { normal[c, r] = normal[r, c] }
        }
        // Penalize every coefficient except the intercept.
        for r in 1..<p { normal[r, r] += alpha * total }
        normal[0, 0] += 1e-9 * total
        guard let l = normal.cholesky() else { return nil }
        return (
            l.transposeBackSubstituted(l.forwardSubstituted(rhsU)),
            l.transposeBackSubstituted(l.forwardSubstituted(rhsV))
        )
    }
}

import Foundation

public enum Stats {
    public static func mean(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    /// Column-wise weighted mean of `rows`.
    public static func weightedMean(_ rows: [[Double]], weights: [Double]) -> [Double] {
        precondition(rows.count == weights.count, "one weight per row")
        guard let width = rows.first?.count else { return [] }
        var sum = [Double](repeating: 0, count: width)
        var total = 0.0
        for (row, w) in zip(rows, weights) {
            for j in 0..<width { sum[j] += w * row[j] }
            total += w
        }
        guard total > 0 else { return sum }
        return sum.map { $0 / total }
    }

    /// Column-wise weighted standard deviation around `center`.
    public static func weightedStandardDeviation(_ rows: [[Double]], weights: [Double], center: [Double]) -> [Double] {
        precondition(rows.count == weights.count, "one weight per row")
        var sum = [Double](repeating: 0, count: center.count)
        var total = 0.0
        for (row, w) in zip(rows, weights) {
            for j in center.indices {
                let d = row[j] - center[j]
                sum[j] += w * d * d
            }
            total += w
        }
        guard total > 0 else { return sum }
        return sum.map { ($0 / total).squareRoot() }
    }

    /// Linear-interpolated quantile, `q` in 0...1.
    public static func quantile(_ values: [Double], _ q: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let position = min(1, max(0, q)) * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = min(sorted.count - 1, lower + 1)
        let fraction = position - Double(lower)
        return sorted[lower] * (1 - fraction) + sorted[upper] * fraction
    }

    public static func median(_ values: [Double]) -> Double {
        quantile(values, 0.5)
    }

    /// Median absolute deviation, scaled to be comparable with a standard deviation.
    public static func robustSpread(_ values: [Double]) -> Double {
        let m = median(values)
        return 1.4826 * median(values.map { abs($0 - m) })
    }
}

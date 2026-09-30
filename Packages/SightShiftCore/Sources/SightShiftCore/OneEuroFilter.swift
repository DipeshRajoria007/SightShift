import Foundation

/// The 1€ filter (Casiez, Roussel & Vogel, CHI 2012): heavy smoothing while the signal is
/// still, light smoothing while it moves fast. Steady gaze stays steady without adding much
/// lag to a deliberate head turn.
public struct OneEuroFilter: Sendable {
    public var minCutoff: Double
    public var beta: Double
    public var derivativeCutoff: Double
    /// A gap longer than this restarts the filter instead of smoothing across it.
    public var resetAfter: Double

    private var previousValue: Double?
    private var previousDerivative = 0.0
    private var previousTime = 0.0

    public init(minCutoff: Double = 1.0, beta: Double = 0.0, derivativeCutoff: Double = 1.0, resetAfter: Double = 0.6) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.derivativeCutoff = derivativeCutoff
        self.resetAfter = resetAfter
    }

    public var value: Double? { previousValue }

    public mutating func reset() {
        previousValue = nil
        previousDerivative = 0
    }

    public mutating func filter(_ x: Double, time: Double) -> Double {
        guard let previous = previousValue, time > previousTime, time - previousTime <= resetAfter else {
            previousValue = x
            previousDerivative = 0
            previousTime = time
            return x
        }
        let dt = max(time - previousTime, 1e-3)
        let derivative = (x - previous) / dt
        let smoothedDerivative = previousDerivative + Self.alpha(cutoff: derivativeCutoff, dt: dt) * (derivative - previousDerivative)
        let cutoff = minCutoff + beta * abs(smoothedDerivative)
        let result = previous + Self.alpha(cutoff: cutoff, dt: dt) * (x - previous)
        previousValue = result
        previousDerivative = smoothedDerivative
        previousTime = time
        return result
    }

    private static func alpha(cutoff: Double, dt: Double) -> Double {
        let tau = 1 / (2 * Double.pi * cutoff)
        return 1 / (1 + tau / dt)
    }
}

/// A 1€ filter per component. Each component is divided by its `scale` before filtering so a
/// single `beta` works for features measured in very different units.
public struct OneEuroVectorFilter: Sendable {
    private var filters: [OneEuroFilter]
    private let scales: [Double]

    public init(scales: [Double], minCutoff: Double, beta: Double, derivativeCutoff: Double = 1.0) {
        self.scales = scales.map { $0 > 0 ? $0 : 1 }
        self.filters = scales.map { _ in OneEuroFilter(minCutoff: minCutoff, beta: beta, derivativeCutoff: derivativeCutoff) }
    }

    public mutating func filter(_ values: [Double], time: Double) -> [Double] {
        precondition(values.count == filters.count, "dimension mismatch")
        return values.indices.map { i in
            filters[i].filter(values[i] / scales[i], time: time) * scales[i]
        }
    }

    public mutating func reset() {
        for i in filters.indices { filters[i].reset() }
    }
}

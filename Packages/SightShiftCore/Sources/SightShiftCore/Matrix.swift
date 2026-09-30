import Foundation

/// A small, dense, row-major matrix.
///
/// SightShift only ever solves problems with about a dozen unknowns, so this favours
/// clarity over speed and avoids pulling in LAPACK.
public struct Matrix: Equatable, Sendable {
    public let rows: Int
    public let cols: Int
    public private(set) var storage: [Double]

    public init(rows: Int, cols: Int, repeating value: Double = 0) {
        precondition(rows >= 0 && cols >= 0, "matrix dimensions must be non-negative")
        self.rows = rows
        self.cols = cols
        self.storage = Array(repeating: value, count: rows * cols)
    }

    public init(_ rowValues: [[Double]]) {
        let columnCount = rowValues.first?.count ?? 0
        precondition(rowValues.allSatisfy { $0.count == columnCount }, "ragged matrix")
        self.rows = rowValues.count
        self.cols = columnCount
        self.storage = rowValues.flatMap { $0 }
    }

    public static func identity(_ n: Int) -> Matrix {
        var m = Matrix(rows: n, cols: n)
        for i in 0..<n { m[i, i] = 1 }
        return m
    }

    public subscript(row: Int, col: Int) -> Double {
        get { storage[row * cols + col] }
        set { storage[row * cols + col] = newValue }
    }

    public var transposed: Matrix {
        var t = Matrix(rows: cols, cols: rows)
        for r in 0..<rows {
            for c in 0..<cols { t[c, r] = self[r, c] }
        }
        return t
    }

    public static func * (lhs: Matrix, rhs: Matrix) -> Matrix {
        precondition(lhs.cols == rhs.rows, "dimension mismatch")
        var out = Matrix(rows: lhs.rows, cols: rhs.cols)
        for i in 0..<lhs.rows {
            for k in 0..<lhs.cols {
                let a = lhs[i, k]
                if a == 0 { continue }
                for j in 0..<rhs.cols { out[i, j] += a * rhs[k, j] }
            }
        }
        return out
    }

    public static func * (lhs: Matrix, rhs: [Double]) -> [Double] {
        precondition(lhs.cols == rhs.count, "dimension mismatch")
        var out = [Double](repeating: 0, count: lhs.rows)
        for i in 0..<lhs.rows {
            var sum = 0.0
            for j in 0..<lhs.cols { sum += lhs[i, j] * rhs[j] }
            out[i] = sum
        }
        return out
    }

    /// Lower-triangular `L` with `self = L·Lᵀ`, or `nil` when `self` is not symmetric positive definite.
    public func cholesky() -> Matrix? {
        precondition(rows == cols, "cholesky needs a square matrix")
        let n = rows
        var l = Matrix(rows: n, cols: n)
        for j in 0..<n {
            var diagonal = self[j, j]
            for k in 0..<j { diagonal -= l[j, k] * l[j, k] }
            guard diagonal.isFinite, diagonal > 1e-12 else { return nil }
            let ljj = diagonal.squareRoot()
            l[j, j] = ljj
            for i in (j + 1)..<n {
                var sum = self[i, j]
                for k in 0..<j { sum -= l[i, k] * l[j, k] }
                l[i, j] = sum / ljj
            }
        }
        return l
    }

    /// Solves `L·x = b` where `self` is lower triangular.
    public func forwardSubstituted(_ b: [Double]) -> [Double] {
        precondition(rows == cols && b.count == rows, "dimension mismatch")
        var x = b
        for i in 0..<rows {
            var sum = x[i]
            for k in 0..<i { sum -= self[i, k] * x[k] }
            x[i] = sum / self[i, i]
        }
        return x
    }

    /// Solves `Lᵀ·x = b` where `self` is lower triangular.
    public func transposeBackSubstituted(_ b: [Double]) -> [Double] {
        precondition(rows == cols && b.count == rows, "dimension mismatch")
        var x = b
        for i in stride(from: rows - 1, through: 0, by: -1) {
            var sum = x[i]
            for k in (i + 1)..<rows { sum -= self[k, i] * x[k] }
            x[i] = sum / self[i, i]
        }
        return x
    }

    /// Solves `self·x = b` for a symmetric positive definite `self`.
    public func solveSymmetricPositiveDefinite(_ b: [Double]) -> [Double]? {
        guard let l = cholesky() else { return nil }
        return l.transposeBackSubstituted(l.forwardSubstituted(b))
    }

    /// Inverse of a lower-triangular matrix.
    public func lowerTriangularInverse() -> Matrix {
        precondition(rows == cols, "inverse needs a square matrix")
        var inverse = Matrix(rows: rows, cols: rows)
        for c in 0..<rows {
            var unit = [Double](repeating: 0, count: rows)
            unit[c] = 1
            let column = forwardSubstituted(unit)
            for r in 0..<rows { inverse[r, c] = column[r] }
        }
        return inverse
    }
}

/// Helpers for plain `[Double]` vectors.
public enum Vec {
    public static func dot(_ a: [Double], _ b: [Double]) -> Double {
        precondition(a.count == b.count, "dimension mismatch")
        var sum = 0.0
        for i in a.indices { sum += a[i] * b[i] }
        return sum
    }

    public static func subtract(_ a: [Double], _ b: [Double]) -> [Double] {
        precondition(a.count == b.count, "dimension mismatch")
        return zip(a, b).map { $0 - $1 }
    }

    public static func add(_ a: [Double], _ b: [Double]) -> [Double] {
        precondition(a.count == b.count, "dimension mismatch")
        return zip(a, b).map { $0 + $1 }
    }

    public static func scale(_ a: [Double], _ s: Double) -> [Double] {
        a.map { $0 * s }
    }

    public static func norm(_ a: [Double]) -> Double {
        dot(a, a).squareRoot()
    }

    public static func distance(_ a: [Double], _ b: [Double]) -> Double {
        norm(subtract(a, b))
    }

    /// Distance from `p` to the segment `a`–`b`.
    public static func distanceToSegment(_ p: [Double], _ a: [Double], _ b: [Double]) -> Double {
        let ab = subtract(b, a)
        let lengthSquared = dot(ab, ab)
        guard lengthSquared > 1e-12 else { return distance(p, a) }
        let t = min(1, max(0, dot(subtract(p, a), ab) / lengthSquared))
        return distance(p, add(a, scale(ab, t)))
    }
}

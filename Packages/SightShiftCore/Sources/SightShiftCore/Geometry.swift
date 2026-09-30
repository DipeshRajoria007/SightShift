import CoreGraphics
import Foundation

/// A position on one screen in unit coordinates: (0, 0) is the top-left corner, (1, 1) the bottom-right.
public struct ScreenPoint: Equatable, Sendable, Codable {
    public var u: Double
    public var v: Double

    public init(u: Double, v: Double) {
        self.u = u
        self.v = v
    }

    public func isWithin(margin: Double) -> Bool {
        u >= -margin && u <= 1 + margin && v >= -margin && v <= 1 + margin
    }

    public var clamped: ScreenPoint {
        ScreenPoint(u: min(1, max(0, u)), v: min(1, max(0, v)))
    }

    /// The matching point in global coordinates, given the screen's frame in the same coordinates
    /// (top-left origin, as used by Quartz and the accessibility API).
    public func location(in frame: CGRect) -> CGPoint {
        CGPoint(x: frame.minX + CGFloat(u) * frame.width, y: frame.minY + CGFloat(v) * frame.height)
    }

    public init(location: CGPoint, in frame: CGRect) {
        self.u = frame.width > 0 ? Double((location.x - frame.minX) / frame.width) : 0.5
        self.v = frame.height > 0 ? Double((location.y - frame.minY) / frame.height) : 0.5
    }
}

extension CGRect {
    public var area: CGFloat { isNull ? 0 : max(0, width) * max(0, height) }

    public var center: CGPoint { CGPoint(x: midX, y: midY) }

    public func overlapArea(with other: CGRect) -> CGFloat {
        intersection(other).area
    }

    /// Intersection over union, 0 when the rectangles don't touch.
    public func overlapRatio(with other: CGRect) -> CGFloat {
        let shared = overlapArea(with: other)
        let union = area + other.area - shared
        return union > 0 ? shared / union : 0
    }
}

/// A screen as the decision logic sees it.
public struct ScreenDescriptor: Equatable, Sendable {
    public var key: String
    /// Frame in global top-left-origin coordinates.
    public var frame: CGRect

    public init(key: String, frame: CGRect) {
        self.key = key
        self.frame = frame
    }
}

extension Array where Element == ScreenDescriptor {
    /// The screen containing `point`, falling back to the nearest one.
    public func screen(containing point: CGPoint) -> ScreenDescriptor? {
        if let exact = first(where: { $0.frame.contains(point) }) { return exact }
        return self.min { lhs, rhs in
            lhs.frame.distanceSquared(to: point) < rhs.frame.distanceSquared(to: point)
        }
    }

    /// The screen holding most of `rect`.
    public func screen(for rect: CGRect) -> ScreenDescriptor? {
        let best = self.max { $0.frame.overlapArea(with: rect) < $1.frame.overlapArea(with: rect) }
        if let best, best.frame.overlapArea(with: rect) > 0 { return best }
        return screen(containing: rect.center)
    }
}

extension CGRect {
    func distanceSquared(to point: CGPoint) -> CGFloat {
        let dx = Swift.max(minX - point.x, 0, point.x - maxX)
        let dy = Swift.max(minY - point.y, 0, point.y - maxY)
        return dx * dx + dy * dy
    }
}

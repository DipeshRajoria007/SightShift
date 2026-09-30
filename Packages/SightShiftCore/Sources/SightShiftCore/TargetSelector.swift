import CoreGraphics
import Foundation

/// Something on a screen that can take keyboard focus (a window or a split pane), or a window
/// that merely covers what's behind it.
public struct FocusTarget: Equatable, Sendable {
    public var id: String
    /// Frame in global top-left-origin coordinates.
    public var frame: CGRect
    /// False for windows that sit in front of others but shouldn't take focus (palettes, helper
    /// windows, SightShift's own windows).
    public var isSelectable: Bool

    public init(id: String, frame: CGRect, isSelectable: Bool = true) {
        self.id = id
        self.frame = frame
        self.isSelectable = isSelectable
    }
}

public enum TargetSelector {
    /// Picks the target you're looking at.
    ///
    /// `targets` must be ordered front to back. A target other than `current` only wins when the
    /// gaze point sits comfortably inside it, away from its edges; near an edge, or over a window
    /// that can't take focus, the answer is `nil` ("not sure"), so a gaze resting on a divider
    /// doesn't flip focus back and forth.
    public static func select(
        point: CGPoint,
        targets: [FocusTarget],
        current: String?,
        marginFraction: CGFloat = 0.12,
        minimumMargin: CGFloat = 16,
        maximumMargin: CGFloat = 90
    ) -> String? {
        guard let front = targets.first(where: { $0.frame.contains(point) }), front.isSelectable else { return nil }
        if front.id == current { return current }
        let margin = min(maximumMargin, max(minimumMargin, min(front.frame.width, front.frame.height) * marginFraction))
        let core = front.frame.insetBy(dx: margin, dy: margin)
        return core.contains(point) ? front.id : nil
    }
}

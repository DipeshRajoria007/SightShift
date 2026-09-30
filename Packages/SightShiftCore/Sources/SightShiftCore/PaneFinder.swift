import CoreGraphics
import Foundation

/// What `PaneFinder` needs to know about one node of an accessibility tree.
public struct PaneNodeInfo<Node> {
    public var role: String?
    public var frame: CGRect?
    public var children: [Node]

    public init(role: String?, frame: CGRect?, children: [Node]) {
        self.role = role
        self.frame = frame
        self.children = children
    }
}

/// A node of an accessibility tree. `inspect()` is called at most once per node, so an
/// implementation backed by the real accessibility API can fetch everything in one round trip.
public protocol PaneNode {
    func inspect() -> PaneNodeInfo<Self>
}

public struct FoundPane<Node> {
    /// The pane's area in the same coordinates as the window frame.
    public var frame: CGRect
    /// The element that should receive focus (a text area inside the pane).
    public var focusElement: Node
}

public struct PaneSearchLimits: Sendable {
    public var maxNodes = 2500
    public var maxDepth = 40
    /// Panes smaller than this share of the window are ignored.
    public var minimumPaneShare: CGFloat = 0.06

    public init() {}
}

private struct SearchEntry<Node> {
    var node: Node
    var parent: Int
    var depth: Int
    var frame: CGRect?
}

/// Finds the split panes of a terminal or editor window by looking for the text areas that
/// receive typing, and measuring the region each one occupies.
public enum PaneFinder {
    /// Roles that take typed text in terminals and editors.
    public static let typingRoles: Set<String> = ["AXTextArea"]

    /// Roles that never contain an editor or terminal, so their subtrees are skipped.
    public static let skippedRoles: Set<String> = [
        "AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton", "AXMenuBar",
        "AXMenu", "AXMenuItem", "AXStaticText", "AXImage", "AXLink", "AXSlider", "AXIncrementor",
        "AXScrollBar", "AXTextField", "AXComboBox", "AXSearchField", "AXTable", "AXOutline",
        "AXList", "AXRow", "AXCell", "AXColumn", "AXToolbar", "AXTabGroup", "AXDisclosureTriangle",
        "AXProgressIndicator", "AXValueIndicator", "AXHeading", "AXRuler",
    ]

    public static func panes<Node: PaneNode>(
        in window: Node,
        windowFrame: CGRect,
        limits: PaneSearchLimits = PaneSearchLimits(),
        deadline: (() -> Bool)? = nil
    ) -> [FoundPane<Node>] {
        typealias Entry = SearchEntry<Node>
        let windowArea = windowFrame.area
        guard windowArea > 0 else { return [] }
        let minimumArea = windowArea * limits.minimumPaneShare

        var entries = [Entry(node: window, parent: -1, depth: 0, frame: windowFrame)]
        var typingEntries: [Int] = []
        var index = 0
        while index < entries.count {
            if entries.count > limits.maxNodes || deadline?() == true { break }
            let entry = entries[index]
            let info = entry.node.inspect()
            if index > 0 { entries[index].frame = info.frame }
            let role = info.role ?? ""
            if typingRoles.contains(role) {
                typingEntries.append(index)
            } else if !skippedRoles.contains(role), entry.depth < limits.maxDepth {
                for child in info.children {
                    entries.append(Entry(node: child, parent: index, depth: entry.depth + 1, frame: nil))
                }
            }
            index += 1
        }

        func paneFrame(for entryIndex: Int) -> CGRect? {
            if let own = entries[entryIndex].frame?.intersection(windowFrame), own.area >= minimumArea {
                return own
            }
            // A tiny text area (editors keep an invisible one at the caret) stands for the
            // nearest ancestor big enough to be a pane.
            var parent = entries[entryIndex].parent
            while parent > 0 {
                if let frame = entries[parent].frame?.intersection(windowFrame), !frame.isNull {
                    if frame.area > windowArea * 0.97 { return nil }
                    if frame.area >= minimumArea { return frame }
                }
                parent = entries[parent].parent
            }
            return nil
        }

        var panes: [FoundPane<Node>] = []
        for entryIndex in typingEntries {
            guard let frame = paneFrame(for: entryIndex) else { continue }
            if panes.contains(where: { $0.frame.overlapRatio(with: frame) > 0.8 }) { continue }
            panes.append(FoundPane(frame: frame, focusElement: entries[entryIndex].node))
        }
        // Keep the innermost regions when one candidate encloses another.
        let candidates = panes
        panes.removeAll { outer in
            candidates.contains { inner in
                inner.frame != outer.frame && outer.frame.contains(inner.frame)
            }
        }
        guard panes.count >= 2 else { return [] }
        // Reading order: top to bottom, then left to right.
        return panes.sorted { lhs, rhs in
            abs(lhs.frame.minY - rhs.frame.minY) > 1 ? lhs.frame.minY < rhs.frame.minY : lhs.frame.minX < rhs.frame.minX
        }
    }
}

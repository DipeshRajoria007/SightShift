import CoreGraphics
import XCTest
@testable import SightShiftCore

/// A hand-built stand-in for an accessibility tree.
final class TreeNode: PaneNode {
    let role: String
    let frame: CGRect?
    let children: [TreeNode]
    let name: String
    private(set) static var inspections = 0

    init(_ role: String, _ frame: CGRect?, name: String = "", _ children: [TreeNode] = []) {
        self.role = role
        self.frame = frame
        self.children = children
        self.name = name
    }

    func inspect() -> PaneNodeInfo<TreeNode> {
        Self.inspections += 1
        return PaneNodeInfo(role: role, frame: frame, children: children)
    }
}

final class PaneFinderTests: XCTestCase {
    private let window = CGRect(x: 0, y: 0, width: 1600, height: 1000)

    func testFindsTerminalSplits() {
        // Like iTerm2 or Ghostty: each pane is a scroll area holding a full-size text area.
        let tree = TreeNode("AXWindow", window, [
            TreeNode("AXButton", CGRect(x: 10, y: 5, width: 20, height: 20)),
            TreeNode("AXSplitGroup", CGRect(x: 0, y: 30, width: 1600, height: 970), [
                TreeNode("AXScrollArea", CGRect(x: 0, y: 30, width: 800, height: 970), [
                    TreeNode("AXTextArea", CGRect(x: 0, y: 30, width: 800, height: 970), name: "left"),
                ]),
                TreeNode("AXScrollArea", CGRect(x: 800, y: 30, width: 800, height: 970), [
                    TreeNode("AXTextArea", CGRect(x: 800, y: 30, width: 800, height: 970), name: "right"),
                ]),
            ]),
        ])
        let panes = PaneFinder.panes(in: tree, windowFrame: window)
        XCTAssertEqual(panes.map(\.focusElement.name), ["left", "right"])
        XCTAssertEqual(panes.first?.frame, CGRect(x: 0, y: 30, width: 800, height: 970))
    }

    func testTinyCaretTextAreasStandForTheirEditor() {
        // Like VS Code: each editor group hides a 1×18 text area at the caret.
        let tree = TreeNode("AXWindow", window, [
            TreeNode("AXGroup", CGRect(x: 0, y: 0, width: 300, height: 1000), [
                TreeNode("AXOutline", CGRect(x: 0, y: 0, width: 300, height: 1000), [
                    TreeNode("AXTextArea", CGRect(x: 10, y: 10, width: 200, height: 900), name: "should be skipped"),
                ]),
            ]),
            TreeNode("AXGroup", CGRect(x: 300, y: 0, width: 650, height: 700), [
                TreeNode("AXGroup", nil, [
                    TreeNode("AXTextArea", CGRect(x: 420, y: 200, width: 1, height: 18), name: "editor 1"),
                ]),
            ]),
            TreeNode("AXGroup", CGRect(x: 950, y: 0, width: 650, height: 700), [
                TreeNode("AXTextArea", CGRect(x: 1100, y: 330, width: 1, height: 18), name: "editor 2"),
            ]),
            TreeNode("AXGroup", CGRect(x: 300, y: 700, width: 1300, height: 300), [
                TreeNode("AXTextArea", CGRect(x: 310, y: 980, width: 1, height: 18), name: "terminal"),
            ]),
        ])
        let panes = PaneFinder.panes(in: tree, windowFrame: window)
        XCTAssertEqual(panes.map(\.focusElement.name), ["editor 1", "editor 2", "terminal"])
        XCTAssertEqual(panes.map(\.frame), [
            CGRect(x: 300, y: 0, width: 650, height: 700),
            CGRect(x: 950, y: 0, width: 650, height: 700),
            CGRect(x: 300, y: 700, width: 1300, height: 300),
        ])
    }

    func testASinglePaneIsNotALayout() {
        let tree = TreeNode("AXWindow", window, [
            TreeNode("AXScrollArea", window, [TreeNode("AXTextArea", window)]),
        ])
        XCTAssertTrue(PaneFinder.panes(in: tree, windowFrame: window).isEmpty)
    }

    func testDuplicateTextAreasCollapse() {
        let tree = TreeNode("AXWindow", window, [
            TreeNode("AXGroup", CGRect(x: 0, y: 0, width: 800, height: 1000), [
                TreeNode("AXTextArea", CGRect(x: 0, y: 0, width: 800, height: 1000), name: "a"),
                TreeNode("AXTextArea", CGRect(x: 0, y: 0, width: 800, height: 990), name: "a-shadow"),
            ]),
            TreeNode("AXTextArea", CGRect(x: 800, y: 0, width: 800, height: 1000), name: "b"),
        ])
        XCTAssertEqual(PaneFinder.panes(in: tree, windowFrame: window).map(\.focusElement.name), ["a", "b"])
    }

    func testStopsAtTheNodeBudget() {
        let many = (0..<50).map { i in TreeNode("AXGroup", CGRect(x: i * 10, y: 0, width: 10, height: 10)) }
        let tree = TreeNode("AXWindow", window, many)
        var limits = PaneSearchLimits()
        limits.maxNodes = 10
        let before = TreeNode.inspections
        _ = PaneFinder.panes(in: tree, windowFrame: window, limits: limits)
        XCTAssertLessThan(TreeNode.inspections - before, 15)
    }
}

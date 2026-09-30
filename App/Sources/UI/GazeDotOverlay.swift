import AppKit

/// An optional translucent dot showing where SightShift thinks you're looking. It lives in a
/// click-through panel above everything else on each screen.
@MainActor
final class GazeDotOverlay {
    private struct Entry {
        let panel: NSPanel
        let dot: NSView
        let display: DisplayInfo
    }

    private static let diameter: CGFloat = 22
    private var entries: [String: Entry] = [:]
    private var visibleKey: String?

    func configure(displays: [DisplayInfo]) {
        hide()
        entries.values.forEach { $0.panel.close() }
        entries = [:]
        for display in displays {
            entries[display.key] = makeEntry(for: display)
        }
    }

    /// `location` is in global top-left coordinates.
    func show(at location: CGPoint, on display: DisplayInfo) {
        guard let entry = entries[display.key] else { return }
        if visibleKey != display.key || !entry.panel.isVisible {
            hide()
            entry.panel.orderFrontRegardless()
            visibleKey = display.key
        }
        let local = CGPoint(
            x: location.x - display.frame.minX - Self.diameter / 2,
            y: display.frame.maxY - location.y - Self.diameter / 2
        )
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.08
            entry.dot.animator().setFrameOrigin(local)
        }
    }

    func hide() {
        if let visibleKey { entries[visibleKey]?.panel.orderOut(nil) }
        visibleKey = nil
    }

    private func makeEntry(for display: DisplayInfo) -> Entry {
        let frame = Displays.cocoaRect(fromGlobal: display.frame)
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.setFrame(frame, display: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false // panels vanish with their app otherwise, and SightShift is rarely active
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false

        let content = NSView(frame: NSRect(origin: .zero, size: frame.size))
        let dot = NSView(frame: NSRect(x: frame.width / 2, y: frame.height / 2, width: Self.diameter, height: Self.diameter))
        dot.wantsLayer = true
        dot.layer?.cornerRadius = Self.diameter / 2
        dot.layer?.backgroundColor = NSColor.systemPink.withAlphaComponent(0.4).cgColor
        dot.layer?.borderColor = NSColor.white.withAlphaComponent(0.9).cgColor
        dot.layer?.borderWidth = 2
        content.addSubview(dot)
        panel.contentView = content
        return Entry(panel: panel, dot: dot, display: display)
    }
}

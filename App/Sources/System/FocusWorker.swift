import AppKit
import ApplicationServices
import SightShiftCore

/// The app and window that currently have keyboard focus.
struct FocusSnapshot: Equatable {
    var pid: pid_t
    var appName: String
    var bundleID: String?
    var windowID: CGWindowID?
    var windowFrame: CGRect?
    /// The screen holding most of the focused window.
    var screenKey: String?
    /// One of SightShift's own windows (settings, diagnostics) is active.
    var isSightShift = false
}

/// Everything on the focused screen that could take focus (or block the view of it), front to back.
struct SameScreenLayout: Equatable {
    var screenKey: String
    var focusedWindowID: CGWindowID
    var targets: [FocusTarget]
    /// The target that has focus right now.
    var currentTargetID: String
    var paneCount: Int
}

/// Apps whose split panes SightShift knows how to focus.
enum PaneApps {
    static let terminals: Set<String> = [
        "com.googlecode.iterm2", "com.apple.Terminal", "com.mitchellh.ghostty", "com.cmuxterm.app",
        "dev.warp.Warp-Stable", "dev.warp.Warp", "net.kovidgoyal.kitty", "com.github.wez.wezterm", "co.zeit.hyper",
    ]
    static let editors: Set<String> = [
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92", // Cursor
        "com.exafunction.windsurf", "com.vscodium", "com.visualstudio.code.oss", "dev.zed.Zed", "dev.zed.Zed-Preview",
        "com.sublimetext.4", "com.sublimetext.3", "com.apple.dt.Xcode", "com.google.android.studio",
    ]
    /// Chromium-based apps only build their accessibility tree when asked to, and asking can
    /// switch VS Code-style editors into screen reader mode, so it's opt-in.
    static let electron: Set<String> = [
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92",
        "com.exafunction.windsurf", "com.vscodium", "com.visualstudio.code.oss", "co.zeit.hyper",
    ]

    static func supportsPanes(_ bundleID: String?, includeElectron: Bool) -> Bool {
        guard let bundleID else { return false }
        if electron.contains(bundleID) { return includeElectron }
        return terminals.contains(bundleID) || editors.contains(bundleID) || bundleID.hasPrefix("com.jetbrains.")
    }

    /// Clicking only focuses a terminal pane; in an editor it would also move the caret.
    static func allowsClickToFocus(_ bundleID: String?) -> Bool {
        bundleID.map(terminals.contains) ?? false
    }
}

/// Watches which window has focus and moves focus around. Everything here runs on one serial
/// queue because accessibility calls can block for a moment on a busy app.
final class FocusWorker {
    struct Callbacks {
        var focusChanged: (FocusSnapshot?) -> Void = { _ in }
        var layoutChanged: (SameScreenLayout?) -> Void = { _ in }
        var log: (String) -> Void = { _ in }
        /// SightShift clicked somewhere itself (system uptime).
        var syntheticClick: (Double) -> Void = { _ in }
    }

    struct Options: Equatable {
        var electronPanes = false
    }

    /// Delivered on the main queue.
    var callbacks = Callbacks()

    private let queue = DispatchQueue(label: "app.sightshift.focus", qos: .userInitiated)
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    private var timer: DispatchSourceTimer?

    // Confined to `queue`.
    private var displays: [DisplayInfo] = []
    private var options = Options()
    private var focus: FocusSnapshot?
    private var focusedWindow: AXUIElement?
    private var recentWindows: [String: [TrackedWindow]] = [:]
    private var paneCache: [CGWindowID: PaneCacheEntry] = [:]
    private var standardWindows: [pid_t: (time: Double, ids: Set<CGWindowID>)] = [:]
    private var manualAccessibilityPIDs: Set<pid_t> = []
    private var layoutWanted = false
    private var lastLayout: SameScreenLayout?
    private var lastLayoutTime = 0.0

    private struct TrackedWindow {
        var pid: pid_t
        var windowID: CGWindowID
        var element: AXUIElement
        var appName: String
    }

    private struct PaneCacheEntry {
        var time: Double
        var lifetime: Double
        var windowFrame: CGRect
        var panes: [FoundPane<AXNode>]
    }

    private struct VisibleWindow {
        var id: CGWindowID
        var pid: pid_t
        var frame: CGRect
        var ownerName: String
        var isOwn: Bool
    }

    private static var now: Double { ProcessInfo.processInfo.systemUptime }

    func start(displays: [DisplayInfo]) {
        queue.async { [self] in
            self.displays = displays
            guard timer == nil else { return }
            AX.limitMessagingTimeout()
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(250), leeway: .milliseconds(40))
            timer.setEventHandler { [weak self] in self?.poll() }
            timer.resume()
            self.timer = timer
        }
    }

    func stop() {
        queue.async { [self] in
            timer?.cancel()
            timer = nil
        }
    }

    func update(displays: [DisplayInfo]) {
        queue.async { [self] in
            self.displays = displays
            recentWindows = recentWindows.filter { key, _ in displays.contains { $0.key == key } }
        }
    }

    func update(options: Options) {
        queue.async { [self] in
            guard options != self.options else { return }
            self.options = options
            paneCache = [:]
            lastLayoutTime = 0
        }
    }

    /// Whether to keep publishing the same-screen layout (windows and panes).
    func setLayoutWanted(_ wanted: Bool) {
        queue.async { [self] in
            layoutWanted = wanted
            if !wanted {
                lastLayout = nil
                deliverLayout(nil)
            }
        }
    }

    // MARK: Polling

    private func poll() {
        guard AX.isTrusted else {
            publishFocus(nil, window: nil)
            return
        }
        let (snapshot, window) = readFocus()
        publishFocus(snapshot, window: window)
        if layoutWanted, Self.now - lastLayoutTime >= 0.4 {
            lastLayoutTime = Self.now
            let layout = computeLayout()
            if layout != lastLayout {
                lastLayout = layout
                deliverLayout(layout)
            }
        }
    }

    private func readFocus() -> (FocusSnapshot?, AXUIElement?) {
        guard let pid = AX.focusedApplicationPID() else { return (nil, nil) }
        if pid == ownPID {
            let snapshot = FocusSnapshot(pid: pid, appName: "SightShift", bundleID: Bundle.main.bundleIdentifier, isSightShift: true)
            return (snapshot, nil)
        }
        let app = AXUIElementCreateApplication(pid)
        let running = NSRunningApplication(processIdentifier: pid)
        let window = AX.element(app, kAXFocusedWindowAttribute)
        let frame = window.flatMap(AX.frame)
        let snapshot = FocusSnapshot(
            pid: pid,
            appName: running?.localizedName ?? "App",
            bundleID: running?.bundleIdentifier,
            windowID: window.flatMap(AX.windowID),
            windowFrame: frame,
            screenKey: frame.flatMap { displays.map(\.descriptor).screen(for: $0)?.key }
        )
        return (snapshot, window)
    }

    private func publishFocus(_ snapshot: FocusSnapshot?, window: AXUIElement?) {
        focusedWindow = window
        if let snapshot, let window, let windowID = snapshot.windowID, let key = snapshot.screenKey {
            remember(TrackedWindow(pid: snapshot.pid, windowID: windowID, element: window, appName: snapshot.appName), on: key)
        }
        guard snapshot != focus else { return }
        focus = snapshot
        let callback = callbacks.focusChanged
        DispatchQueue.main.async { callback(snapshot) }
    }

    /// Most recently focused windows per screen, newest first.
    private func remember(_ window: TrackedWindow, on screenKey: String) {
        if recentWindows[screenKey]?.first?.windowID == window.windowID { return }
        for key in recentWindows.keys { recentWindows[key]?.removeAll { $0.windowID == window.windowID } }
        var list = recentWindows[screenKey] ?? []
        list.insert(window, at: 0)
        if list.count > 12 { list.removeLast(list.count - 12) }
        recentWindows[screenKey] = list
    }

    // MARK: Same-screen layout

    private func computeLayout() -> SameScreenLayout? {
        guard let focus, !focus.isSightShift, let windowID = focus.windowID, let windowFrame = focus.windowFrame,
              let screenKey = focus.screenKey, let display = displays.first(where: { $0.key == screenKey }) else { return nil }

        var panes: [FoundPane<AXNode>] = []
        var currentTargetID = Self.windowTargetID(windowID)
        if PaneApps.supportsPanes(focus.bundleID, includeElectron: options.electronPanes), let element = focusedWindow {
            panes = self.panes(windowID: windowID, element: element, frame: windowFrame, pid: focus.pid, bundleID: focus.bundleID)
            if let focused = AX.element(AXUIElementCreateApplication(focus.pid), kAXFocusedUIElementAttribute),
               let active = panes.first(where: { Self.element(focused, isInside: $0) }) {
                currentTargetID = Self.paneTargetID(windowID, active.frame)
            }
        }
        // The focused window: its panes first, then the rest of it (sidebar, tabs, title bar),
        // which counts as "where you already are" so the window behind never shows through.
        func focusedWindowTargets(_ frame: CGRect) -> [FocusTarget] {
            panes.map { FocusTarget(id: Self.paneTargetID(windowID, $0.frame), frame: $0.frame) }
                + [FocusTarget(id: currentTargetID, frame: frame)]
        }

        var targets: [FocusTarget] = []
        var placedFocusedWindow = false
        for window in visibleWindows(includingOwn: true) where window.frame.intersects(display.frame) {
            if window.id == windowID {
                targets += focusedWindowTargets(window.frame)
                placedFocusedWindow = true
                continue
            }
            // Other windows can take focus if they're real windows mostly on this screen. The
            // rest (palettes, helper windows, SightShift's own) still hide what's behind them.
            let selectable = !window.isOwn && window.frame.width >= 120 && window.frame.height >= 80
                && window.frame.intersection(display.frame).area > window.frame.area * 0.5
                && isStandardWindow(window)
            targets.append(FocusTarget(
                id: selectable ? Self.windowTargetID(window.id) : "x:\(window.id)",
                frame: window.frame,
                isSelectable: selectable
            ))
        }
        if !placedFocusedWindow {
            targets.insert(contentsOf: focusedWindowTargets(windowFrame), at: 0)
        }
        return SameScreenLayout(screenKey: screenKey, focusedWindowID: windowID, targets: targets, currentTargetID: currentTargetID, paneCount: panes.count)
    }

    private func panes(windowID: CGWindowID, element: AXUIElement, frame: CGRect, pid: pid_t, bundleID: String?) -> [FoundPane<AXNode>] {
        let now = Self.now
        if let cached = paneCache[windowID], now - cached.time < cached.lifetime, cached.windowFrame == frame {
            return cached.panes
        }
        if let bundleID, PaneApps.electron.contains(bundleID), !manualAccessibilityPIDs.contains(pid) {
            // What screen readers do: ask Chromium to expose its accessibility tree.
            AX.set(AXUIElementCreateApplication(pid), "AXManualAccessibility", kCFBooleanTrue)
            manualAccessibilityPIDs.insert(pid)
        }
        let deadline = now + 0.12
        let panes = PaneFinder.panes(in: AXNode(element: element), windowFrame: frame, deadline: { Self.now > deadline })
        // Walking a big tree (an Electron editor, say) costs the app time too; do it less often.
        let lifetime = Self.now - now > 0.06 ? 5.0 : 1.5
        paneCache[windowID] = PaneCacheEntry(time: now, lifetime: lifetime, windowFrame: frame, panes: panes)
        if paneCache.count > 24 {
            paneCache = paneCache.filter { now - $0.value.time < 10 }
        }
        return panes
    }

    /// Whether keyboard focus sits inside `pane`.
    private func hasFocus(_ pane: FoundPane<AXNode>, app: AXUIElement) -> Bool {
        guard let focused = AX.element(app, kAXFocusedUIElementAttribute) else { return false }
        return Self.element(focused, isInside: pane)
    }

    private static func element(_ element: AXUIElement, isInside pane: FoundPane<AXNode>) -> Bool {
        if CFEqual(element, pane.focusElement.element) { return true }
        // Editors keep a tiny text area at the caret; a whole window doesn't count.
        guard let frame = AX.frame(element), frame.area < pane.frame.area * 1.5 else { return false }
        return pane.frame.insetBy(dx: -2, dy: -2).contains(frame.center)
    }

    static func windowTargetID(_ windowID: CGWindowID) -> String { "w:\(windowID)" }

    static func paneTargetID(_ windowID: CGWindowID, _ frame: CGRect) -> String {
        "p:\(windowID):\(Int(frame.minX)),\(Int(frame.minY)),\(Int(frame.width)),\(Int(frame.height))"
    }

    private func deliverLayout(_ layout: SameScreenLayout?) {
        let callback = callbacks.layoutChanged
        DispatchQueue.main.async { callback(layout) }
    }

    private func log(_ message: String) {
        let callback = callbacks.log
        DispatchQueue.main.async { callback(message) }
    }

    // MARK: Window list

    /// Ordinary windows on screen, front to back.
    private func visibleWindows(includingOwn: Bool = false) -> [VisibleWindow] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return list.compactMap { info -> VisibleWindow? in
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  includingOwn || pid != ownPID,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  frame.width >= 20, frame.height >= 20,
                  ((info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0.05 else { return nil }
            return VisibleWindow(id: id, pid: pid, frame: frame, ownerName: info[kCGWindowOwnerName as String] as? String ?? "App", isOwn: pid == ownPID)
        }
    }

    /// Real document and dialog windows, as opposed to the helper windows some apps (Chrome, for
    /// one) keep on screen for tab strips, bubbles and drop-downs.
    private func isStandardWindow(_ window: VisibleWindow) -> Bool {
        guard !window.isOwn else { return false }
        let now = Self.now
        if let cached = standardWindows[window.pid], now - cached.time < 2, cached.ids.contains(window.id) {
            return true
        }
        if let cached = standardWindows[window.pid], now - cached.time < 0.5 {
            return cached.ids.contains(window.id)
        }
        var ids = Set<CGWindowID>()
        for element in AX.elements(AXUIElementCreateApplication(window.pid), kAXWindowsAttribute) {
            let subrole = AX.string(element, kAXSubroleAttribute)
            guard subrole == nil || subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole else { continue }
            if let id = AX.windowID(element) { ids.insert(id) }
        }
        standardWindows[window.pid] = (now, ids)
        if standardWindows.count > 40 {
            standardWindows = standardWindows.filter { now - $0.value.time < 10 }
        }
        return ids.contains(window.id)
    }

    private func axWindow(pid: pid_t, windowID: CGWindowID) -> AXUIElement? {
        AX.elements(AXUIElementCreateApplication(pid), kAXWindowsAttribute).first { AX.windowID($0) == windowID }
    }

    // MARK: Actions

    /// Focuses a window on `screenKey` and, if asked, brings the pointer along.
    ///
    /// - Parameter pointerJustUsed: when you've just moved the pointer onto that screen, the
    ///   window under it wins over the one you used last, and the pointer stays where you put it.
    func switchToScreen(_ screenKey: String, movePointer: Bool, rememberedPointer: CGPoint?, pointerJustUsed: Bool) {
        queue.async { [self] in
            guard let display = displays.first(where: { $0.key == screenKey }) else { return }
            let visible = visibleWindows()
            let onScreen = visible.filter { display.frame.contains($0.frame.center) }
            let cursor = CGEvent(source: nil)?.location
            let pointerAlreadyThere = cursor.map(display.frame.contains) ?? false
            var target: (window: TrackedWindow, frame: CGRect)?

            if pointerAlreadyThere, pointerJustUsed, let cursor,
               let under = visible.first(where: { $0.frame.contains(cursor) && isStandardWindow($0) }),
               let element = axWindow(pid: under.pid, windowID: under.id) {
                target = (TrackedWindow(pid: under.pid, windowID: under.id, element: element, appName: under.ownerName), under.frame)
            }
            if target == nil {
                for candidate in recentWindows[screenKey] ?? [] {
                    if let match = onScreen.first(where: { $0.id == candidate.windowID }) {
                        target = (candidate, match.frame)
                        break
                    }
                }
            }
            if target == nil {
                for window in onScreen where isStandardWindow(window) {
                    guard let element = axWindow(pid: window.pid, windowID: window.id) else { continue }
                    target = (TrackedWindow(pid: window.pid, windowID: window.id, element: element, appName: window.ownerName), window.frame)
                    break
                }
            }

            if let target {
                focus(target.window)
                log("Focused \(target.window.appName) on \(display.name)")
            } else {
                log("Nothing to focus on \(display.name)")
            }

            let pointerInTarget = cursor.map { point in target.map { $0.frame.contains(point) } ?? false } ?? false
            if movePointer, !(pointerAlreadyThere && (pointerJustUsed || pointerInTarget)) {
                let area = target.map { $0.frame.intersection(display.frame) } ?? display.frame
                let remembered = rememberedPointer.flatMap { area.insetBy(dx: 4, dy: 4).contains($0) ? $0 : nil }
                warpPointer(to: remembered ?? area.center)
            }
        }
    }

    /// Focuses a window or pane from the latest same-screen layout.
    func focusTarget(_ targetID: String, allowClick: Bool) {
        queue.async { [self] in
            if targetID.hasPrefix("w:"), let windowID = CGWindowID(targetID.dropFirst(2)) {
                guard let window = visibleWindows().first(where: { $0.id == windowID }),
                      let element = axWindow(pid: window.pid, windowID: windowID) else { return }
                focus(TrackedWindow(pid: window.pid, windowID: windowID, element: element, appName: window.ownerName))
                log("Focused \(window.ownerName) window")
            } else if targetID.hasPrefix("p:"), let focus, let windowID = focus.windowID,
                      let pane = paneCache[windowID]?.panes.first(where: { Self.paneTargetID(windowID, $0.frame) == targetID }) {
                focusPane(pane, focus: focus, allowClick: allowClick)
            }
        }
    }

    private func focus(_ window: TrackedWindow) {
        let usedPrivateAPI = PrivateAPI.activate(pid: window.pid, windowID: window.windowID)
        AX.set(window.element, kAXMainAttribute, kCFBooleanTrue)
        AX.perform(window.element, kAXRaiseAction)
        if usedPrivateAPI { usleep(60_000) }
        if !usedPrivateAPI || AX.focusedApplicationPID() != window.pid {
            AX.set(AXUIElementCreateApplication(window.pid), kAXFrontmostAttribute, kCFBooleanTrue)
            let pid = window.pid
            DispatchQueue.main.async {
                NSRunningApplication(processIdentifier: pid)?.activate()
            }
        }
        lastLayoutTime = 0 // refresh the layout soon
    }

    private func focusPane(_ pane: FoundPane<AXNode>, focus: FocusSnapshot, allowClick: Bool) {
        let app = AXUIElementCreateApplication(focus.pid)
        if hasFocus(pane, app: app) { return }
        lastLayoutTime = 0
        AX.set(pane.focusElement.element, kAXFocusedAttribute, kCFBooleanTrue)
        for _ in 0..<5 {
            usleep(40_000)
            if hasFocus(pane, app: app) {
                log("Focused a pane in \(focus.appName)")
                return
            }
        }
        // Some terminals don't let other apps focus a split directly; a click in it does.
        guard allowClick, PaneApps.allowsClickToFocus(focus.bundleID) else {
            log("\(focus.appName) didn't accept pane focus")
            return
        }
        let point = pane.frame.center
        guard clickWouldLand(at: point, in: pane, pid: focus.pid) else {
            log("Didn't click: something covers the pane in \(focus.appName)")
            return
        }
        click(at: point)
        log("Clicked a pane in \(focus.appName)")
    }

    /// Whether a click at `point` would reach `pane` rather than some other window on top of it.
    private func clickWouldLand(at point: CGPoint, in pane: FoundPane<AXNode>, pid: pid_t) -> Bool {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AX.systemWide, Float(point.x), Float(point.y), &hit) == .success,
              let hit, AX.pid(hit) == pid else { return false }
        if CFEqual(hit, pane.focusElement.element) { return true }
        guard let frame = AX.frame(hit) else { return false }
        return pane.frame.insetBy(dx: -2, dy: -2).contains(frame.center) || frame.contains(pane.frame)
    }

    private func click(at point: CGPoint) {
        let original = CGEvent(source: nil)?.location
        let source = CGEventSource(stateID: .hidSystemState)
        let callback = callbacks.syntheticClick
        let now = Self.now
        DispatchQueue.main.async { callback(now) }
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { continue }
            event.flags = [] // a held ⌘ would turn this into a ⌘-click
            event.setIntegerValueField(.eventSourceUserData, value: ActivityMonitor.syntheticEventTag)
            event.post(tap: .cghidEventTap)
            usleep(12_000)
        }
        if let original { warpPointer(to: original) }
    }

    private func warpPointer(to point: CGPoint) {
        CGWarpMouseCursorPosition(point)
        CGAssociateMouseAndMouseCursorPosition(1)
    }
}

import AppKit

/// The menu bar icon and its menu.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private unowned let controller: AppController

    init(controller: AppController) {
        self.controller = controller
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        item.button?.toolTip = "SightShift"
        refresh()
    }

    func refresh() {
        let symbol: String
        if controller.isPaused || controller.isSuspended {
            symbol = "eye.slash"
        } else if controller.needsAttention {
            symbol = "eye.trianglebadge.exclamationmark"
        } else {
            symbol = "eye"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "SightShift")
            ?? NSImage(systemSymbolName: "eye", accessibilityDescription: "SightShift")
        image?.isTemplate = true
        item.button?.image = image
        item.button?.appearsDisabled = controller.isPaused
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        for line in statusLines() {
            let header = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
        }
        for fix in fixes() {
            menu.addItem(fix)
        }
        menu.addItem(.separator())

        let pause = add(to: menu, controller.isPaused ? "Resume SightShift" : "Pause SightShift", #selector(togglePause))
        pause.toolTip = "Shortcut: \(controller.hotKeyDescription)"
        applyShortcut(to: pause)
        menu.addItem(.separator())

        add(to: menu, "Calibrate All Screens…", #selector(calibrateAll)).isEnabled = !controller.isCalibrating
        if controller.displays.count > 1 {
            let recalibrate = NSMenuItem(title: "Calibrate One Screen", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for display in controller.displays {
                let entry = NSMenuItem(title: display.name, action: #selector(calibrateOne(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = display.key
                entry.state = controller.profile.screens[display.key] != nil ? .on : .off
                submenu.addItem(entry)
            }
            recalibrate.submenu = submenu
            menu.addItem(recalibrate)
        }
        let dot = add(to: menu, "Show Gaze Dot", #selector(toggleGazeDot))
        dot.state = controller.settings.showGazeDot ? .on : .off
        menu.addItem(.separator())

        add(to: menu, "Settings…", #selector(openSettings), key: ",")
        add(to: menu, "Diagnostics…", #selector(openDiagnostics))
        add(to: menu, "Setup Guide…", #selector(openOnboarding))
        menu.addItem(.separator())
        add(to: menu, "About SightShift", #selector(openAbout))
        add(to: menu, "Quit SightShift", #selector(quit), key: "q")
    }

    private func statusLines() -> [String] {
        if controller.isCalibrating { return ["Calibrating…"] }
        if controller.isPaused { return ["Paused"] }
        if controller.isSuspended { return ["Paused while the Mac is locked"] }
        if controller.cameraStatus != .authorized { return ["Needs camera access"] }
        if !controller.accessibilityTrusted { return ["Needs Accessibility access"] }
        if !controller.hasModel { return ["Calibrate to get started"] }
        if let problem = controller.cameraProblem { return ["Camera problem: \(problem)"] }
        var lines: [String] = []
        if !controller.status.faceVisible {
            lines.append("Watching · can't see your face")
        } else if let screen = controller.status.gazeScreenName {
            lines.append("Watching · looking at \(screen)")
        } else {
            lines.append("Watching")
        }
        let missing = controller.uncalibratedDisplays
        if !missing.isEmpty {
            lines.append("Not calibrated: \(missing.map(\.name).joined(separator: ", "))")
        }
        return lines
    }

    private func fixes() -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        if controller.cameraStatus != .authorized {
            items.append(make("Allow Camera Access…", #selector(fixCamera)))
        }
        if !controller.accessibilityTrusted {
            items.append(make("Allow Accessibility Access…", #selector(fixAccessibility)))
        }
        let missing = controller.uncalibratedDisplays
        if controller.hasModel, !missing.isEmpty {
            items.append(make(missing.count == 1 ? "Calibrate \(missing[0].name)…" : "Calibrate New Screens…", #selector(calibrateMissing)))
        }
        return items
    }

    private func applyShortcut(to item: NSMenuItem) {
        let settings = controller.settings
        guard let shortcut = KeyNames.menuKeyEquivalent(keyCode: settings.hotKeyCode, modifiers: settings.hotKeyModifiers) else {
            item.title += " (\(controller.hotKeyDescription))"
            return
        }
        item.keyEquivalent = shortcut.key
        item.keyEquivalentModifierMask = shortcut.mask
    }

    @discardableResult
    private func add(to menu: NSMenu, _ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = make(title, action, key: key)
        menu.addItem(item)
        return item
    }

    private func make(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func togglePause() { controller.togglePause() }
    @objc private func calibrateAll() { controller.startCalibration() }
    @objc private func calibrateMissing() { controller.startCalibration(only: controller.uncalibratedDisplays.map(\.key)) }
    @objc private func openSettings() { controller.showSettings() }
    @objc private func openDiagnostics() { controller.showDiagnostics() }
    @objc private func openOnboarding() { controller.showOnboarding() }
    @objc private func openAbout() { controller.showAbout() }
    @objc private func fixCamera() { controller.requestCamera() }
    @objc private func fixAccessibility() { controller.requestAccessibility() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func toggleGazeDot() {
        UserDefaults.standard.set(!controller.settings.showGazeDot, forKey: PrefKey.showGazeDot)
    }

    @objc private func calibrateOne(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        controller.startCalibration(only: [key])
    }
}

import Carbon.HIToolbox
import Foundation
import SightShiftCore

enum PrefKey {
    static let cameraID = "cameraID"
    static let screenSwitchDelay = "screenSwitchDelay"
    static let headTurnThreshold = "headTurnThreshold"
    static let movePointer = "movePointer"
    static let sameScreenFocus = "sameScreenFocus"
    static let paneDelay = "paneDelay"
    static let clickToFocusPanes = "clickToFocusPanes"
    static let waitWhileTyping = "waitWhileTyping"
    static let typingPause = "typingPause"
    static let pointerPause = "pointerPause"
    static let learnFromClicks = "learnFromClicks"
    static let showGazeDot = "showGazeDot"
    static let electronPanes = "electronPanes"
    static let accessibilityPromptShown = "accessibilityPromptShown"
    static let hotKeyCode = "hotKeyCode"
    static let hotKeyModifiers = "hotKeyModifiers"
}

enum Defaults {
    static let screenSwitchDelay = 0.3
    static let headTurnThreshold = 0.5
    static let paneDelay = 0.35
    static let typingPause = 2.0
    static let pointerPause = 1.5
    // ⌃⌥⌘G. ⇧⌘G would be the obvious pick, but it is Find Previous in most apps and
    // Go to Folder in Finder, and a global shortcut would swallow it everywhere.
    static let hotKeyCode = kVK_ANSI_G
    static let hotKeyModifiers = cmdKey | optionKey | controlKey

    static func register() {
        UserDefaults.standard.register(defaults: [
            PrefKey.cameraID: "",
            PrefKey.screenSwitchDelay: screenSwitchDelay,
            PrefKey.headTurnThreshold: headTurnThreshold,
            PrefKey.movePointer: true,
            PrefKey.sameScreenFocus: true,
            PrefKey.paneDelay: paneDelay,
            PrefKey.clickToFocusPanes: true,
            PrefKey.waitWhileTyping: true,
            PrefKey.typingPause: typingPause,
            PrefKey.pointerPause: pointerPause,
            PrefKey.learnFromClicks: true,
            PrefKey.showGazeDot: false,
            PrefKey.electronPanes: false,
            PrefKey.hotKeyCode: hotKeyCode,
            PrefKey.hotKeyModifiers: hotKeyModifiers,
        ])
    }
}

/// A snapshot of the user's settings, re-read whenever defaults change.
struct AppSettings: Equatable {
    var cameraID: String?
    var screenSwitchDelay: Double
    var headTurnThreshold: Double
    var movePointer: Bool
    var sameScreenFocus: Bool
    var paneDelay: Double
    var clickToFocusPanes: Bool
    var waitWhileTyping: Bool
    var typingPause: Double
    var pointerPause: Double
    var learnFromClicks: Bool
    var showGazeDot: Bool
    var electronPanes: Bool
    var hotKeyCode: UInt32
    var hotKeyModifiers: UInt32

    static func current(_ defaults: UserDefaults = .standard) -> AppSettings {
        let camera = defaults.string(forKey: PrefKey.cameraID) ?? ""
        return AppSettings(
            cameraID: camera.isEmpty ? nil : camera,
            screenSwitchDelay: defaults.double(forKey: PrefKey.screenSwitchDelay),
            headTurnThreshold: defaults.double(forKey: PrefKey.headTurnThreshold),
            movePointer: defaults.bool(forKey: PrefKey.movePointer),
            sameScreenFocus: defaults.bool(forKey: PrefKey.sameScreenFocus),
            paneDelay: defaults.double(forKey: PrefKey.paneDelay),
            clickToFocusPanes: defaults.bool(forKey: PrefKey.clickToFocusPanes),
            waitWhileTyping: defaults.bool(forKey: PrefKey.waitWhileTyping),
            typingPause: defaults.double(forKey: PrefKey.typingPause),
            pointerPause: defaults.double(forKey: PrefKey.pointerPause),
            learnFromClicks: defaults.bool(forKey: PrefKey.learnFromClicks),
            showGazeDot: defaults.bool(forKey: PrefKey.showGazeDot),
            electronPanes: defaults.bool(forKey: PrefKey.electronPanes),
            hotKeyCode: UInt32(truncatingIfNeeded: defaults.integer(forKey: PrefKey.hotKeyCode)),
            hotKeyModifiers: UInt32(truncatingIfNeeded: defaults.integer(forKey: PrefKey.hotKeyModifiers))
        )
    }

    var guards: GuardSettings {
        GuardSettings(waitWhileTyping: waitWhileTyping, typingPause: typingPause, pointerPause: pointerPause)
    }
}

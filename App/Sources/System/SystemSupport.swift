import AppKit
import AVFoundation
import Carbon.HIToolbox
import ServiceManagement
import UserNotifications

/// Pauses tracking while the Mac sleeps, locks, shows the screen saver or switches user.
@MainActor
final class SystemEvents {
    var onChange: ((Bool) -> Void)?

    private var asleep = false
    private var screensAsleep = false
    private var locked = false
    private var screenSaver = false
    private var sessionInactive = false
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    var isSuspended: Bool { asleep || screensAsleep || locked || screenSaver || sessionInactive }

    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        watch(workspace, NSWorkspace.willSleepNotification) { $0.asleep = true }
        watch(workspace, NSWorkspace.didWakeNotification) { $0.asleep = false }
        watch(workspace, NSWorkspace.screensDidSleepNotification) { $0.screensAsleep = true }
        watch(workspace, NSWorkspace.screensDidWakeNotification) { $0.screensAsleep = false }
        watch(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.sessionInactive = true }
        watch(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.sessionInactive = false }
        let distributed = DistributedNotificationCenter.default()
        watch(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.locked = true }
        watch(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.locked = false }
        watch(distributed, Notification.Name("com.apple.screensaver.didstart")) { $0.screenSaver = true }
        watch(distributed, Notification.Name("com.apple.screensaver.didstop")) { $0.screenSaver = false }
    }

    private func watch(_ center: NotificationCenter, _ name: Notification.Name, _ update: @escaping (SystemEvents) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let wasSuspended = self.isSuspended
                update(self)
                if wasSuspended != self.isSuspended { self.onChange?(self.isSuspended) }
            }
        }
        observers.append((center, token))
    }
}

enum Permissions {
    static var cameraStatus: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .video) }

    static func requestCamera(_ completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    static func openCameraSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    private static func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }
}

enum Notifier {
    /// Posts a notification, asking for permission the first time there's something to say.
    static func post(id: String, title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        center.requestAuthorization(options: [.alert]) { granted, _ in
            if granted { center.add(request) }
        }
    }
}

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

/// A system-wide keyboard shortcut, registered with the Carbon hot key API (which, unlike an
/// event tap, needs no extra permission). It stays registered until `invalidate()` or deinit.
final class HotKey {
    private final class WeakRef {
        weak var hotKey: HotKey?
        init(_ hotKey: HotKey) { self.hotKey = hotKey }
    }

    private static var registry: [UInt32: WeakRef] = [:]
    private static var nextID: UInt32 = 1
    private static var handlerInstalled = false

    private let id: UInt32
    private let action: () -> Void
    private var reference: EventHotKeyRef?

    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.id = Self.nextID
        self.action = action
        Self.nextID += 1
        Self.installHandler()
        let hotKeyID = EventHotKeyID(signature: OSType(0x5353_4854), id: id) // 'SSHT'
        guard RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &reference) == noErr else {
            return nil
        }
        Self.registry[id] = WeakRef(self)
    }

    deinit {
        invalidate()
    }

    func invalidate() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
        Self.registry[id] = nil
    }

    private static func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            guard status == noErr else { return status }
            DispatchQueue.main.async { HotKey.registry[hotKeyID.id]?.hotKey?.action() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}

enum KeyNames {
    /// "⌃⌥⌘G" style description of a Carbon key code and modifier mask.
    static func describe(keyCode: UInt32, modifiers: UInt32) -> String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + name(for: Int(keyCode))
    }

    /// Whether a shortcut is safe to take over system-wide: it needs ⌃, or ⌥ together with ⌘.
    /// ⌘ alone would swallow everyday shortcuts such as ⌘C, and ⌥ alone types characters on many
    /// keyboard layouts (⌥L is @ on a German keyboard).
    static func isAcceptableGlobalShortcut(modifiers: UInt32) -> Bool {
        modifiers & UInt32(controlKey) != 0
            || (modifiers & UInt32(optionKey) != 0 && modifiers & UInt32(cmdKey) != 0)
    }

    /// The key equivalent and modifier mask for showing a shortcut in a menu.
    static func menuKeyEquivalent(keyCode: UInt32, modifiers: UInt32) -> (key: String, mask: NSEvent.ModifierFlags)? {
        let functionKeys: [Int: Int] = [
            kVK_F1: NSF1FunctionKey, kVK_F2: NSF2FunctionKey, kVK_F3: NSF3FunctionKey, kVK_F4: NSF4FunctionKey,
            kVK_F5: NSF5FunctionKey, kVK_F6: NSF6FunctionKey, kVK_F7: NSF7FunctionKey, kVK_F8: NSF8FunctionKey,
            kVK_F9: NSF9FunctionKey, kVK_F10: NSF10FunctionKey, kVK_F11: NSF11FunctionKey, kVK_F12: NSF12FunctionKey,
            kVK_LeftArrow: NSLeftArrowFunctionKey, kVK_RightArrow: NSRightArrowFunctionKey,
            kVK_UpArrow: NSUpArrowFunctionKey, kVK_DownArrow: NSDownArrowFunctionKey,
        ]
        let plain: [Int: String] = [kVK_Space: " ", kVK_Return: "\r", kVK_Tab: "\t", kVK_Delete: "\u{8}", kVK_Escape: "\u{1b}"]
        let key: String
        if let function = functionKeys[Int(keyCode)], let scalar = UnicodeScalar(function) {
            key = String(Character(scalar))
        } else if let special = plain[Int(keyCode)] {
            key = special
        } else if let typed = typedCharacter(for: Int(keyCode)), typed.count == 1, !typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            key = typed.lowercased()
        } else {
            return nil
        }
        var mask: NSEvent.ModifierFlags = []
        if modifiers & UInt32(controlKey) != 0 { mask.insert(.control) }
        if modifiers & UInt32(optionKey) != 0 { mask.insert(.option) }
        if modifiers & UInt32(shiftKey) != 0 { mask.insert(.shift) }
        if modifiers & UInt32(cmdKey) != 0 { mask.insert(.command) }
        return (key, mask)
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        return modifiers
    }

    private static func name(for keyCode: Int) -> String {
        let special: [Int: String] = [
            kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫", kVK_Escape: "⎋",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        ]
        if let name = special[keyCode] { return name }
        return typedCharacter(for: keyCode)?.uppercased() ?? "Key \(keyCode)"
    }

    /// The character the key produces on the current keyboard layout.
    private static func typedCharacter(for keyCode: Int) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
        return data.withUnsafeBytes { raw -> String? in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var deadKeys: UInt32 = 0
            var length = 0
            var characters = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, characters.count, &length, &characters
            )
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: characters, count: length)
        }
    }
}

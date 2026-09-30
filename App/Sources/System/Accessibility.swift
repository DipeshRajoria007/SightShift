import AppKit
import ApplicationServices
import SightShiftCore

/// Thin wrappers over the accessibility C API.
enum AX {
    static let systemWide = AXUIElementCreateSystemWide()

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that sends the user to the Accessibility list.
    static func requestTrust() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Caps how long a single call may wait on a busy app (the default is several seconds).
    static func limitMessagingTimeout(_ seconds: Float = 0.4) {
        AXUIElementSetMessagingTimeout(systemWide, seconds)
    }

    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = value(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        (value(element, attribute) as? [AXUIElement]) ?? []
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute) as? String
    }

    /// Several attributes in one round trip; missing ones come back as `nil`.
    static func values(_ element: AXUIElement, _ attributes: [String]) -> [CFTypeRef?] {
        var result: CFArray?
        let status = AXUIElementCopyMultipleAttributeValues(element, attributes as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &result)
        guard status == .success, let array = result as? [AnyObject], array.count == attributes.count else {
            return Array(repeating: nil, count: attributes.count)
        }
        return array.map { $0 }
    }

    static func point(_ value: CFTypeRef?) -> CGPoint? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }

    static func size(_ value: CFTypeRef?) -> CGSize? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
    }

    /// Frame in global top-left coordinates.
    static func frame(_ element: AXUIElement) -> CGRect? {
        let values = values(element, [kAXPositionAttribute, kAXSizeAttribute])
        guard let origin = point(values[0]), let size = size(values[1]) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    static func pid(_ element: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        return AXUIElementGetPid(element, &pid) == .success ? pid : nil
    }

    static func windowID(_ element: AXUIElement) -> CGWindowID? {
        guard let getWindow = PrivateAPI.axGetWindow else { return nil }
        var id: CGWindowID = 0
        return getWindow(element, &id) == .success && id != 0 ? id : nil
    }

    @discardableResult
    static func set(_ element: AXUIElement, _ attribute: String, _ value: CFTypeRef) -> AXError {
        AXUIElementSetAttributeValue(element, attribute as CFString, value)
    }

    @discardableResult
    static func perform(_ element: AXUIElement, _ action: String) -> AXError {
        AXUIElementPerformAction(element, action as CFString)
    }

    static func focusedApplicationPID() -> pid_t? {
        element(systemWide, kAXFocusedApplicationAttribute).flatMap(pid)
    }
}

/// An accessibility element as `PaneFinder` sees it.
struct AXNode: PaneNode {
    let element: AXUIElement

    func inspect() -> PaneNodeInfo<AXNode> {
        let values = AX.values(element, [kAXRoleAttribute, kAXPositionAttribute, kAXSizeAttribute, kAXChildrenAttribute])
        var frame: CGRect?
        if let origin = AX.point(values[1]), let size = AX.size(values[2]) {
            frame = CGRect(origin: origin, size: size)
        }
        let children = (values[3] as? [AXUIElement])?.map(AXNode.init) ?? []
        return PaneNodeInfo(role: values[0] as? String, frame: frame, children: children)
    }
}

/// Undocumented but long-stable functions that window managers such as AltTab and yabai rely
/// on. They are looked up at run time; when one is missing SightShift falls back to the
/// public accessibility API.
enum PrivateAPI {
    typealias AXGetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    typealias SetFrontProcess = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> CGError
    typealias PostEventRecord = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> CGError
    typealias ProcessForPID = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

    private static let applicationServices = "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices"
    private static let skyLight = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"

    static let axGetWindow: AXGetWindow? = symbol("_AXUIElementGetWindow", in: applicationServices)
    static let setFrontProcess: SetFrontProcess? = symbol("_SLPSSetFrontProcessWithOptions", in: skyLight)
    static let postEventRecord: PostEventRecord? = symbol("SLPSPostEventRecordTo", in: skyLight)
    static let processForPID: ProcessForPID? = symbol("GetProcessForPID", in: applicationServices)

    private static let userGenerated: UInt32 = 0x200

    private static func symbol<T>(_ name: String, in path: String) -> T? {
        let handle = dlopen(path, RTLD_LAZY) ?? UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        guard let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }

    /// Brings one specific window of an app forward and makes it key, the way a click would,
    /// without clicking. Returns false when the private functions aren't available.
    static func activate(pid: pid_t, windowID: CGWindowID) -> Bool {
        guard let setFrontProcess, let postEventRecord, let processForPID else { return false }
        var psn = ProcessSerialNumber()
        guard processForPID(pid, &psn) == noErr else { return false }
        guard setFrontProcess(&psn, windowID, userGenerated) == .success else { return false }

        // Two synthetic "window became key" records, as sent by the window server on a click.
        var bytes = [UInt8](repeating: 0, count: 0xF8)
        bytes[0x04] = 0xF8
        bytes[0x3A] = 0x10
        withUnsafeBytes(of: windowID.littleEndian) { raw in
            for (offset, byte) in raw.enumerated() { bytes[0x3C + offset] = byte }
        }
        for offset in 0x20..<0x30 { bytes[offset] = 0xFF }
        for kind: UInt8 in [0x01, 0x02] {
            bytes[0x08] = kind
            bytes.withUnsafeMutableBufferPointer { buffer in
                _ = postEventRecord(&psn, buffer.baseAddress!)
            }
        }
        return true
    }
}

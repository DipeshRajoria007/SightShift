import AppKit
import SightShiftCore

struct DisplayInfo: Equatable, Identifiable {
    let id: CGDirectDisplayID
    /// Survives reboots and reconnections, so calibration can be matched to the right screen.
    let key: String
    let name: String
    /// Global coordinates with the origin at the top-left of the primary display, y down
    /// (the convention used by Quartz window lists and the accessibility API).
    let frame: CGRect
    let isBuiltin: Bool

    var descriptor: ScreenDescriptor { ScreenDescriptor(key: key, frame: frame) }
}

enum Displays {
    /// Active displays, left to right and then top to bottom.
    static func current() -> [DisplayInfo] {
        NSScreen.screens.compactMap { screen -> DisplayInfo? in
            guard let id = displayID(of: screen) else { return nil }
            return DisplayInfo(
                id: id,
                key: key(for: id),
                name: screen.localizedName,
                frame: CGDisplayBounds(id),
                isBuiltin: CGDisplayIsBuiltin(id) != 0
            )
        }
        .sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }

    static func screen(for display: DisplayInfo) -> NSScreen? {
        NSScreen.screens.first { displayID(of: $0) == display.id }
    }

    static func key(for id: CGDirectDisplayID) -> String {
        if let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
           let string = CFUUIDCreateString(nil, uuid) {
            return string as String
        }
        return "display-\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(CGDisplaySerialNumber(id))"
    }

    /// Height of the primary display: the pivot between Cocoa's bottom-left and Quartz's
    /// top-left coordinates.
    static var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? CGDisplayBounds(CGMainDisplayID()).height
    }

    static func cocoaRect(fromGlobal rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func globalPoint(fromCocoa point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    /// The pointer position in global top-left coordinates.
    static var cursorLocation: CGPoint {
        CGEvent(source: nil)?.location ?? globalPoint(fromCocoa: NSEvent.mouseLocation)
    }
}

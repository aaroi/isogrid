import AppKit

/// AppKit puts the origin at the bottom-left of the primary display; Accessibility and
/// CGWindowList put it at the top-left. Everything window-related in Isogrid uses the
/// top-left ("AX") space, and converts at the AppKit boundary.
enum Screen {
    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    static func flip(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static var mouse: CGPoint {
        let point = NSEvent.mouseLocation
        return CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    static func containing(_ point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.axFrame.contains(point) } ?? NSScreen.main
    }

    static var underMouse: NSScreen? { containing(mouse) }
}

extension NSScreen {
    var axFrame: CGRect { Screen.flip(frame) }
    var axVisibleFrame: CGRect { Screen.flip(visibleFrame) }

    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    private static var keys: [CGDirectDisplayID: String] = [:]

    /// Display IDs get reused after a reconnect, so cached keys are dropped whenever displays change.
    static func forgetKeys() {
        keys.removeAll()
    }

    /// The display's UUID. It outlives the display ID across reboots, but macOS can still issue
    /// a new one when a monitor reconnects through another port or hub; `Settings` handles that.
    /// Cached, because the gap controller asks on every mouse move.
    var persistentKey: String {
        if let key = Self.keys[displayID] { return key }
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return localizedName }
        let key = CFUUIDCreateString(nil, uuid) as String
        Self.keys[displayID] = key
        return key
    }
}

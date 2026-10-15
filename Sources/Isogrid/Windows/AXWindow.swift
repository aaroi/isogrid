// Switching off AXEnhancedUserInterface while moving a window, and correcting a second pass
// after a display clamps it, follow Rectangle (MIT License, Copyright (c) 2019-2026 Ryan
// Hanson). See THIRD_PARTY_NOTICES.md.

import AppKit

@_silgen_name("_AXUIElementGetWindow")
private nonisolated func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

/// A window of another app, driven through the Accessibility API. Accessibility calls are
/// synchronous IPC to the other app, so moves run off the main thread to keep motion smooth.
nonisolated struct AXWindow: @unchecked Sendable {
    let element: AXUIElement
    let app: AXUIElement
    let windowID: CGWindowID

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func promptForTrust() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func all(pid: pid_t) -> [AXWindow] {
        let app = AXUIElementCreateApplication(pid)
        // An app that is beachballing must not freeze us for the system default of several seconds.
        AXUIElementSetMessagingTimeout(app, 0.25)
        guard let windows = app.value(kAXWindowsAttribute) as? [AXUIElement] else { return [] }
        return windows.compactMap { element in
            var id = CGWindowID(0)
            guard _AXUIElementGetWindow(element, &id) == .success else { return nil }
            return AXWindow(element: element, app: app, windowID: id)
        }
    }

    static func windowID(of element: AXUIElement) -> CGWindowID? {
        var id = CGWindowID(0)
        return _AXUIElementGetWindow(element, &id) == .success ? id : nil
    }

    static func find(_ windowID: CGWindowID, pid: pid_t) -> AXWindow? {
        all(pid: pid).first { $0.windowID == windowID }
    }

    /// Looks up many windows while asking each app for its window list only once.
    struct Resolver {
        private var windows: [pid_t: [AXWindow]] = [:]

        mutating func window(_ id: CGWindowID, pid: pid_t) -> AXWindow? {
            if windows[pid] == nil { windows[pid] = AXWindow.all(pid: pid) }
            return windows[pid]?.first { $0.windowID == id }
        }
    }

    /// Excludes sheets, palettes, popovers and minimized windows.
    var isStandard: Bool {
        element.value(kAXSubroleAttribute) as? String == kAXStandardWindowSubrole
            && element.value(kAXMinimizedAttribute) as? Bool != true
    }

    var frame: CGRect? {
        guard let origin: CGPoint = element.axValue(kAXPositionAttribute, .cgPoint),
              let size: CGSize = element.axValue(kAXSizeAttribute, .cgSize) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    var pid: pid_t {
        var pid: pid_t = 0
        AXUIElementGetPid(app, &pid)
        return pid
    }

    /// `target` is in top-left screen coordinates.
    func setFrame(_ target: CGRect) {
        let current = frame
        guard current != target else { return }
        // With AXEnhancedUserInterface on, Chromium and Electron apps animate every
        // Accessibility resize, so a snap visibly crawls into place.
        let enhanced = app.value("AXEnhancedUserInterface") as? Bool == true
        if enhanced { app.set("AXEnhancedUserInterface", kCFBooleanFalse) }
        defer { if enhanced { app.set("AXEnhancedUserInterface", kCFBooleanTrue) } }

        // Each call makes the app redraw, so use two calls in the order that keeps the window
        // on screen, shrinking before moving and moving before growing.
        if let current, target.width <= current.width, target.height <= current.height {
            setSize(target.size)
            setPosition(target.origin)
        } else {
            setPosition(target.origin)
            setSize(target.size)
        }
        // macOS clamps a window to the display it was on, so a move across displays, or a
        // window pushed against the Dock, may need one more pass.
        guard let settled = frame else { return }
        if abs(settled.width - target.width) > 1 || abs(settled.height - target.height) > 1 { setSize(target.size) }
        if abs(settled.minX - target.minX) > 1 || abs(settled.minY - target.minY) > 1 { setPosition(target.origin) }
    }

    var isMinimized: Bool { element.value(kAXMinimizedAttribute) as? Bool == true }

    func unminimize() {
        element.set(kAXMinimizedAttribute, kCFBooleanFalse)
    }

    /// Brings the window above other windows without activating its app.
    func raise() {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }

    func makeMain() {
        element.set(kAXMainAttribute, kCFBooleanTrue)
    }

    /// Activates the app and makes this its main, focused window.
    func focus() {
        app.set(kAXFrontmostAttribute, kCFBooleanTrue)
        element.set(kAXMainAttribute, kCFBooleanTrue)
        raise()
    }

    private func setSize(_ size: CGSize) {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return }
        element.set(kAXSizeAttribute, value)
    }

    private func setPosition(_ origin: CGPoint) {
        var origin = origin
        guard let value = AXValueCreate(.cgPoint, &origin) else { return }
        element.set(kAXPositionAttribute, value)
    }
}

nonisolated extension AXUIElement {
    func value(_ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success ? value : nil
    }

    func set(_ attribute: String, _ value: CFTypeRef) {
        AXUIElementSetAttributeValue(self, attribute as CFString, value)
    }

    func axValue<T>(_ attribute: String, _ type: AXValueType) -> T? {
        guard let value = value(attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return withUnsafeTemporaryAllocation(of: T.self, capacity: 1) { buffer in
            // CF types can't be cast conditionally; the type ID check above makes this one safe.
            guard let pointer = buffer.baseAddress, AXValueGetValue(value as! AXValue, type, pointer) else { return nil }
            return pointer.pointee
        }
    }
}

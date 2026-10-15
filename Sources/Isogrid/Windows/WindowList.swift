import AppKit

/// A window as the window server sees it. Cheap to query and needs no permissions,
/// so it is used for hit-testing and z-order before touching Accessibility.
nonisolated struct WindowInfo: Sendable {
    let id: CGWindowID
    let pid: pid_t
    /// Top-left screen coordinates.
    let bounds: CGRect
}

nonisolated enum WindowList {
    /// Normal-level windows on the current Space, front-most first.
    static func onScreen() -> [WindowInfo] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        return parse(list)
    }

    /// Every window that still exists, including minimized ones and those on other Spaces.
    static func allIDs() -> Set<CGWindowID> {
        Set(parse(CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID)).map(\.id))
    }

    static func info(for id: CGWindowID) -> WindowInfo? {
        parse(CGWindowListCopyWindowInfo(.optionIncludingWindow, id)).first
    }

    /// Activation reorders windows a moment after the app becomes active; anything raised
    /// before that lands below whatever was in front. Waits until `id` is the front window.
    static func waitUntilFront(_ id: CGWindowID, timeout: Duration = .milliseconds(500)) async {
        let clock = ContinuousClock()
        let end = clock.now + timeout
        while clock.now < end, onScreen().first?.id != id {
            try? await Task.sleep(for: .milliseconds(15))
        }
    }

    static func topWindow(at point: CGPoint) -> WindowInfo? {
        onScreen().first { $0.bounds.contains(point) }
    }

    private static func parse(_ list: CFArray?) -> [WindowInfo] {
        guard let list = list as? [[String: Any]] else { return [] }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return list.compactMap { entry in
            guard entry[kCGWindowLayer as String] as? Int == 0,
                  (entry[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let id = entry[kCGWindowNumber as String] as? Int,
                  let pid = entry[kCGWindowOwnerPID as String] as? Int,
                  pid != Int(ownPID),
                  let rawBounds = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: rawBounds),
                  bounds.width > 40, bounds.height > 40
            else { return nil }
            return WindowInfo(id: CGWindowID(id), pid: pid_t(pid), bounds: bounds)
        }
    }
}

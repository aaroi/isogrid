import AppKit
import IsogridCore

/// Makes a set behave as one window. Focusing any member, with a click, ⌘Tab or Mission
/// Control, brings the rest of its set up with it.
final class GroupFocus {
    private let settings = Settings.shared
    private var observers: [pid_t: AXObserver] = [:]
    private var pending: Task<Void, Never>?
    /// Raising windows fires focus notifications of its own; ignore those.
    private var quietUntil = Date.distantPast
    /// The window focused at the previous change, to tell entering a set from moving within it.
    private var lastFocusedID: CGWindowID?

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.focusChanged() }
        }
        refreshObservers()
    }

    /// Watches window focus inside each app that has windows in a set, so switching between two
    /// windows of the same app counts too.
    func refreshObservers() {
        let pids = Set(settings.library.sets.flatMap { $0.members.map(\.pid) })
        for pid in observers.keys where !pids.contains(pid) {
            if let observer = observers.removeValue(forKey: pid) {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            }
        }
        for pid in pids where observers[pid] == nil {
            var observer: AXObserver?
            guard AXObserverCreate(pid, focusCallback, &observer) == .success, let observer else { continue }
            let app = AXUIElementCreateApplication(pid)
            // Lives as long as the app, so observers can hold it unretained.
            let refcon = Unmanaged.passUnretained(self).toOpaque()
            AXObserverAddNotification(observer, app, kAXFocusedWindowChangedNotification as CFString, refcon)
            AXObserverAddNotification(observer, app, kAXMainWindowChangedNotification as CFString, refcon)
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            observers[pid] = observer
        }
    }

    /// Ignores focus changes for a while, during a set recall that reorders windows itself.
    func hold(for seconds: TimeInterval) {
        quietUntil = Date().addingTimeInterval(seconds)
        pending?.cancel()
    }

    fileprivate func focusChanged() {
        guard Date() > quietUntil else { return }
        pending?.cancel()
        // Let the focus change settle; Mission Control fires several in a row.
        pending = Task {
            try? await Task.sleep(for: .milliseconds(40))
            guard !Task.isCancelled, let first = focusedWindow() else { return }
            // While you switch away, an app can report its previous window as focused for a
            // moment. Act only on a focus that is still the same a beat later.
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled, let second = focusedWindow(), second == first else { return }
            raiseGroup(around: second.id, in: second.app)
        }
    }

    private struct Focus: Equatable {
        let id: CGWindowID
        let app: pid_t
    }

    private func focusedWindow() -> Focus? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.25)
        // CF types can't be cast conditionally; the type ID check makes the cast below safe.
        guard let focused = appElement.value(kAXFocusedWindowAttribute), CFGetTypeID(focused) == AXUIElementGetTypeID(),
              let id = AXWindow.windowID(of: focused as! AXUIElement) else { return nil }
        return Focus(id: id, app: app.processIdentifier)
    }

    private func raiseGroup(around focusedID: CGWindowID, in pid: pid_t) {
        let previous = lastFocusedID
        lastFocusedID = focusedID
        guard let set = settings.library.sets.first(where: { $0.members.contains { $0.windowID == focusedID } }) else { return }
        // Whichever set you're in is the one drags and gap resizes on this display work with.
        if let screen = NSScreen.screens.first(where: { $0.persistentKey == set.displayKey }) {
            if settings.grid(for: screen) != set.grid { settings.setGrid(set.grid, for: screen) }
            if settings.library.active(on: set.displayKey)?.id != set.id { settings.library.touch(set.id, at: .now) }
        }
        let onScreen = WindowList.onScreen()
        // The window that just lost focus is never raised, because closing a member moves focus
        // to another member while the closed one is still fading out.
        let excluded: Set<CGWindowID> = previous.flatMap { $0 == focusedID ? nil : [$0] } ?? []

        let memberIDs = Set(set.members.map(\.windowID))
        let visibleMembers = onScreen.filter { memberIDs.contains($0.id) }
        guard visibleMembers.count > 1, !Self.isOnTop(visibleMembers, in: onScreen) else { return }

        var resolver = AXWindow.Resolver()
        let others: [AXWindow] = set.members.sorted { $0.cell > $1.cell }.compactMap { member in
            guard member.windowID != focusedID, !excluded.contains(member.windowID),
                  visibleMembers.contains(where: { $0.id == member.windowID }) else { return nil }
            // Never raise something that isn't a normal open window right now.
            return resolver.window(member.windowID, pid: member.pid).flatMap { $0.isStandard ? $0 : nil }
        }
        guard !others.isEmpty, let focusedWindow = resolver.window(focusedID, pid: pid) else { return }

        settings.library.touch(set.id, at: .now)
        quietUntil = Date().addingTimeInterval(0.4)
        Task { await Self.raise(others, thenKeep: focusedWindow) }
    }

    /// True when no window outside the group covers part of a member.
    private static func isOnTop(_ members: [WindowInfo], in list: [WindowInfo]) -> Bool {
        let ids = Set(members.map(\.id))
        for (index, window) in list.enumerated() where !ids.contains(window.id) {
            let below = list[(index + 1)...].filter { ids.contains($0.id) }
            if below.contains(where: { $0.bounds.intersection(window.bounds).width > 8 && $0.bounds.intersection(window.bounds).height > 8 }) {
                return false
            }
        }
        return true
    }

    /// Raising another app's window slots it in just below the front window, but raising a
    /// window of the front app puts it on top, so the clicked window is raised again last and
    /// stays main. No app is activated, so nothing flickers.
    @concurrent nonisolated private static func raise(_ windows: [AXWindow], thenKeep focused: AXWindow) async {
        await WindowList.waitUntilFront(focused.windowID)
        for window in windows { window.raise() }
        focused.raise()
        focused.makeMain()
    }
}

private nonisolated func focusCallback(_: AXObserver, _: AXUIElement, _: CFString, refcon: UnsafeMutableRawPointer?) {
    // Raw pointers aren't Sendable; the address crosses into the main actor as an integer.
    let address = UInt(bitPattern: refcon)
    // Observer sources are on the main run loop.
    MainActor.assumeIsolated {
        guard let pointer = UnsafeRawPointer(bitPattern: address) else { return }
        Unmanaged<GroupFocus>.fromOpaque(pointer).takeUnretainedValue().focusChanged()
    }
}

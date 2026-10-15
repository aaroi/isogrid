import AppKit
import IsogridCore

/// Arranges windows into grids and recalls window sets.
final class Tiler {
    struct Move: Sendable {
        let window: AXWindow
        let frame: CGRect
    }

    private let overlay: Overlay
    private let groups: GroupFocus
    private let settings = Settings.shared
    private var transition: Task<Void, Never>?
    /// When set, only these apps' windows are tiled. Used by the end-to-end test.
    var onlyPIDs: Set<pid_t>?

    /// Returns once the current tile, recall or raise has finished.
    func idle() async {
        await transition?.value
    }

    init(overlay: Overlay, groups: GroupFocus) {
        self.overlay = overlay
        self.groups = groups
    }

    /// Makes `layout` the display's grid, with equal cells, and arranges its windows into it.
    func apply(_ layout: TileLayout, on screen: NSScreen) {
        settings.setGrid(TileGrid(layout), for: screen)
        tile(on: screen)
    }

    /// Tiles the visible windows on a display. The tiled windows become a set.
    func tile(on screen: NSScreen) {
        let grid = settings.grid(for: screen)
        let cells = grid.cellFrames(in: screen.axVisibleFrame, gap: settings.gap)
        let windows = visibleWindows(on: screen)
        let assignment = GridMath.assign(windows: windows.map(\.info.bounds), to: cells)
        var flights: [Overlay.Flight] = []
        var moves: [Move] = []
        var members: [WindowSet.Member] = []
        for (window, cell) in zip(windows, assignment) {
            guard let cell else { continue }
            flights.append(Overlay.Flight(from: window.info.bounds, to: cells[cell], icon: Self.icon(window.info.pid)))
            moves.append(Move(window: window.ax, frame: cells[cell]))
            members.append(.init(windowID: window.info.id, pid: window.info.pid, cell: cell))
        }
        guard !moves.isEmpty else { return }

        pruneClosedWindows()
        // Saving the grid also records the display, so its sets can follow it to a new ID.
        settings.setGrid(grid, for: screen)
        settings.library.record(grid: grid, members: members, on: screen.persistentKey, at: .now)
        run(flights, moves: moves, on: screen)
    }

    /// Brings a set to the front, restoring minimized members and re-snapping any that moved.
    /// Recalling one set is how the others go to the back.
    /// `covered` means something already hides the screen (the overview), so no frost of our own.
    func recall(slot: Int, covered: Bool = false) {
        pruneClosedWindows()
        guard let set = settings.library.set(inSlot: slot),
              let screen = NSScreen.screens.first(where: { $0.persistentKey == set.displayKey }) ?? Screen.underMouse else { return }
        settings.setGrid(set.grid, for: screen)
        settings.library.touch(set.id, at: .now)

        let cells = set.grid.cellFrames(in: screen.axVisibleFrame, gap: settings.gap)
        let onScreen = Dictionary(WindowList.onScreen().map { ($0.id, $0.bounds) }, uniquingKeysWith: { first, _ in first })
        var resolver = AXWindow.Resolver()
        var flights: [Overlay.Flight] = []
        var moves: [Move] = []
        var raise: [AXWindow] = []
        var closed: [CGWindowID] = []
        for member in set.members.sorted(by: { $0.cell > $1.cell }) where cells.indices.contains(member.cell) {
            guard let window = resolver.window(member.windowID, pid: member.pid) else { continue }
            let current = onScreen[member.windowID]
            // Off screen and not minimized means you closed or hid it, so it leaves the set.
            guard current != nil || window.isMinimized else {
                closed.append(member.windowID)
                continue
            }
            let cell = cells[member.cell]
            raise.append(window)
            if current.map({ !$0.isClose(to: cell) }) ?? true {
                // A window that was minimized or on another Space appears in its cell without flying in.
                flights.append(Overlay.Flight(from: current ?? cell, to: cell, icon: Self.icon(member.pid)))
                moves.append(Move(window: window, frame: cell))
            }
        }
        if !closed.isEmpty { settings.library.remove(windowIDs: Set(closed)) }
        guard !raise.isEmpty else { return }
        // Recall reorders windows itself; group focus mustn't react to the focus changes it causes.
        groups.hold(for: 1.2)

        if moves.isEmpty || covered {
            // With everything in place, or the overview hiding the screen, raise without animation.
            transition = Task { await Self.perform(moves, raising: raise) }
        } else {
            run(flights, moves: moves, raising: raise, on: screen)
        }
    }

    func preview(on screen: NSScreen) {
        overlay.preview(cells: settings.grid(for: screen).cellFrames(in: screen.axVisibleFrame, gap: settings.gap), on: screen)
    }

    /// Accessibility calls block until the other app answers, so they run off the main thread.
    /// `raising` is ordered back to front; its last window ends up focused.
    @concurrent nonisolated static func perform(_ moves: [Move], raising: [AXWindow] = []) async {
        for window in raising where window.isMinimized {
            window.unminimize()
        }
        for move in moves {
            move.window.setFrame(move.frame)
        }
        await settle(moves)
        // Activate only the app of the front-most member; a raise slots the rest in below it,
        // even across apps, without switching apps and flickering the menu bar.
        guard let front = raising.last else { return }
        front.focus()
        await WindowList.waitUntilFront(front.windowID)
        for window in raising.dropLast().reversed() { window.raise() }
        // Raising a window of the front app puts it on top, so restore the front one last.
        front.raise()
        front.makeMain()
    }

    /// Some apps apply a resize a beat later, and the window server can finish a drag after
    /// a drop has placed the window. Check again shortly after and correct what didn't land.
    /// What still doesn't land shows the window's minimum size.
    @concurrent nonisolated static func settle(_ moves: [Move]) async {
        var pending = moves
        for delay in [80, 220] {
            try? await Task.sleep(for: .milliseconds(delay))
            pending = pending.filter { move in move.window.frame.map { !$0.isClose(to: move.frame) } ?? false }
            if pending.isEmpty { break }
            for move in pending { move.window.setFrame(move.frame) }
        }
        var kept: [CGWindowID: CGSize] = [:]
        if !pending.isEmpty { try? await Task.sleep(for: .milliseconds(120)) }
        for move in pending {
            guard let frame = move.window.frame, !frame.isClose(to: move.frame) else { continue }
            kept[move.window.windowID] = frame.size
            let app = NSRunningApplication(processIdentifier: move.window.pid)?.localizedName ?? "?"
            log.notice("\(app, privacy: .public) kept \(frame.debugDescription, privacy: .public) instead of \(move.frame.debugDescription, privacy: .public)")
        }
        await MainActor.run { MinimumSizes.record(moves, kept: kept) }
    }

    func pruneClosedWindows() {
        let alive = WindowList.allIDs()
        settings.library.prune(keeping: alive)
        MinimumSizes.prune(keeping: alive)
    }

    static func icon(_ pid: pid_t) -> NSImage? {
        NSRunningApplication(processIdentifier: pid)?.icon
    }

    private func run(_ flights: [Overlay.Flight], moves: [Move], raising: [AXWindow] = [], on screen: NSScreen) {
        transition?.cancel()
        overlay.beginTransition(flights, on: screen)
        transition = Task {
            // Let the frost come up before anything moves underneath it.
            try? await Task.sleep(for: .milliseconds(110))
            await Self.perform(moves, raising: raising)
            await overlay.endTransition()
        }
    }

    private func visibleWindows(on screen: NSScreen) -> [(ax: AXWindow, info: WindowInfo)] {
        let area = screen.axFrame
        var resolver = AXWindow.Resolver()
        return WindowList.onScreen().compactMap { info in
            guard area.contains(info.bounds.center), onlyPIDs?.contains(info.pid) ?? true,
                  let window = resolver.window(info.id, pid: info.pid), window.isStandard else { return nil }
            return (window, info)
        }
    }
}

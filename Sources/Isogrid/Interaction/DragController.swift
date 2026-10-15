import AppKit
import IsogridCore

/// Watches window drags system-wide. While the drag modifier is held, the grid appears and
/// releasing the mouse drops the window into the cell under the pointer. Dropping onto a cell
/// that already has a window swaps the two.
final class DragController {
    private struct Drag {
        let window: WindowInfo
        var isMovingWindow = false
        var screen: NSScreen?
        var cells: [CGRect] = []
        /// The cell the dragged window came from, if it was in the grid.
        var origin: Int?
        /// The front-most other window in each cell.
        var occupants: [Int: WindowInfo] = [:]
        var target: Int?
    }

    private let overlay: Overlay
    private let settings = Settings.shared
    private var monitor: Any?
    private var drag: Drag?

    init(overlay: Overlay) {
        self.overlay = overlay
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .flagsChanged]) { [weak self] event in
            self?.handle(event)
        }
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            drag = WindowList.topWindow(at: Screen.mouse).map { Drag(window: $0) }
        case .leftMouseDragged, .flagsChanged:
            update(flags: event.modifierFlags)
        case .leftMouseUp:
            drop()
        default:
            break
        }
    }

    private func update(flags: NSEvent.ModifierFlags) {
        guard var drag else { return }
        let held = flags.contains(settings.dragModifier.flags)

        // A drag only counts once the window itself has moved, which rules out text
        // selection, scrollbars and resizing, since they all leave the origin alone.
        if held, !drag.isMovingWindow, let now = WindowList.info(for: drag.window.id),
           now.bounds.origin != drag.window.bounds.origin, now.bounds.size == drag.window.bounds.size {
            drag.isMovingWindow = true
        }

        let point = Screen.mouse
        if held, drag.isMovingWindow, let screen = Screen.containing(point) {
            if screen != drag.screen {
                drag.screen = screen
                drag.cells = settings.grid(for: screen).cellFrames(in: screen.axVisibleFrame, gap: settings.gap)
                (drag.origin, drag.occupants) = Self.survey(drag.cells, dragging: drag.window, on: screen)
            }
            if let index = GridMath.cell(nearest: point, in: drag.cells) {
                overlay.track(cells: drag.cells, target: index, on: screen)
                drag.target = index
                previewSwap(for: drag)
            }
        } else if drag.target != nil {
            overlay.cancel()
            drag.target = nil
        }
        self.drag = drag
    }

    /// While hovering an occupied cell, a frosted copy of its window glides to where the swap
    /// will put it, so you can see the outcome before letting go.
    private func previewSwap(for drag: Drag) {
        guard let target = drag.target, let occupant = drag.occupants[target],
              let destination = GridMath.swapDestination(from: drag.origin, into: target,
                                                         occupied: Set(drag.occupants.keys), cells: drag.cells) else {
            return overlay.clearSwap()
        }
        overlay.previewSwap(from: drag.cells[target], to: drag.cells[destination], icon: Tiler.icon(occupant.pid))
    }

    private func drop() {
        defer { drag = nil }
        guard let drag, let target = drag.target, let screen = drag.screen else { return }
        Self.drop(drag.window, origin: drag.origin, into: target, occupants: drag.occupants, cells: drag.cells,
                  on: screen, overlay: overlay)
    }

    /// Moves the dropped window into `target`, and the window already there to its swap
    /// destination. Shared with the end-to-end test, which drops without a mouse.
    static func drop(_ window: WindowInfo, origin: Int?, into target: Int, occupants: [Int: WindowInfo], cells: [CGRect],
                     on screen: NSScreen, overlay: Overlay, completion: @escaping () -> Void = {}) {
        guard let dragged = AXWindow.find(window.id, pid: window.pid) else {
            overlay.cancel()
            return completion()
        }
        var moves = [Tiler.Move(window: dragged, frame: cells[target])]
        var placements = [(window, target)]
        if let occupant = occupants[target],
           let destination = GridMath.swapDestination(from: origin, into: target, occupied: Set(occupants.keys), cells: cells),
           let displaced = AXWindow.find(occupant.id, pid: occupant.pid) {
            moves.append(Tiler.Move(window: displaced, frame: cells[destination]))
            placements.append((occupant, destination))
        }

        let settings = Settings.shared
        let key = screen.persistentKey
        if settings.library.active(on: key)?.grid.layout == settings.layout(for: screen) {
            for (window, cell) in placements {
                settings.library.place(windowID: window.id, pid: window.pid, inCell: cell, on: key)
            }
        }
        overlay.beginDrop()
        Task {
            await Tiler.perform(moves)
            overlay.endDrop()
            completion()
        }
    }

    /// The dragged window's own cell, and the front-most other window in each cell.
    static func survey(_ cells: [CGRect], dragging window: WindowInfo, on screen: NSScreen) -> (origin: Int?, occupants: [Int: WindowInfo]) {
        let origin = GridMath.match(windows: [window.bounds], to: cells).first ?? nil
        let others = WindowList.onScreen().filter { $0.id != window.id && screen.axFrame.contains($0.bounds.center) }
        var occupants: [Int: WindowInfo] = [:]
        for (info, cell) in zip(others, GridMath.match(windows: others.map(\.bounds), to: cells)) {
            guard let cell, occupants[cell] == nil else { continue }
            occupants[cell] = info
        }
        return (origin, occupants)
    }
}

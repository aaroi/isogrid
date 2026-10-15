import AppKit
import IsogridCore

/// Drag the gap between tiled windows to resize them. A plain drag resizes the two windows on
/// either side of the pointer; holding Shift moves the whole line, across every row or column
/// whose edge lines up. Shift can be pressed or released mid-drag.
/// An event tap claims clicks in a live gap, so they never fall through to the desktop.
final class GapController {
    /// The grid a gap belongs to, which is the grid of the set whose windows border it. A drag
    /// never resizes against another set's cells or moves windows outside that set.
    private struct Context {
        let screen: NSScreen
        let area: CGRect
        let grid: TileGrid
        let setID: UUID?
        /// Window IDs allowed to move; nil for a grid without a set, where any tiled window may.
        let members: Set<CGWindowID>?
    }

    private struct Hover {
        let context: Context
        let divider: TileGrid.Divider
        let isLive: Bool
    }

    private struct Session {
        let context: Context
        let start: CGPoint
        /// Pointer distance from the gap's centre at mouse-down, so the gap never jumps to the pointer.
        let grabOffset: CGFloat
        /// Every tiled window the line could move; a pair drag uses two of them.
        let windows: [(window: AXWindow, cell: Int)]
        var grid: TileGrid
        var divider: TileGrid.Divider
        var scope: TileGrid.Scope
        /// Where the pointer asks the gap's centre to be.
        var position: CGFloat
        var snapped = false
    }

    /// How close, in points, a gap has to come to another edge to line up with it.
    private static let snapDistance: CGFloat = 12

    private let overlay: Overlay
    private let settings = Settings.shared
    private var tap: CFMachPort?
    private var hover: Hover?
    private var session: Session?

    init(overlay: Overlay) {
        self.overlay = overlay
    }

    /// Needs Accessibility access; returns false until it is granted.
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let types: [CGEventType] = [.mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp, .flagsChanged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        // The controller lives as long as the app, so the tap can hold it unretained.
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: gapTapCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        return true
    }

    fileprivate func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    /// Returns true when the event belongs to a gap drag and must not reach other apps.
    fileprivate func handle(_ type: CGEventType, at point: CGPoint, shift: Bool) -> Bool {
        let scope: TileGrid.Scope = shift ? .line : .pair
        switch type {
        case .mouseMoved:
            updateHover(at: point, scope: scope)
            return false
        case .flagsChanged:
            if session != nil { drag(to: point, scope: scope) } else { updateHover(at: point, scope: scope, force: true) }
            return false
        case .leftMouseDown:
            return begin(at: point, scope: scope)
        case .leftMouseDragged:
            guard session != nil else { return false }
            drag(to: point, scope: scope)
            return true
        case .leftMouseUp:
            guard session != nil else { return false }
            end()
            return true
        default:
            return false
        }
    }

    /// A whole gap drag without the mouse, for the end-to-end test.
    func simulate(from start: CGPoint, to end: CGPoint, line: Bool) async -> Bool {
        let scope: TileGrid.Scope = line ? .line : .pair
        updateHover(at: start, scope: scope, force: true)
        guard begin(at: start, scope: scope) else { return false }
        drag(to: end, scope: scope)
        await self.end()?.value
        return true
    }

    // MARK: Hover

    /// Grids that could own a gap on this display, starting with its sets from most recently
    /// used and ending with the display's own grid.
    private func contexts(on screen: NSScreen) -> [Context] {
        let area = screen.axVisibleFrame
        let key = screen.persistentKey
        let sets = settings.library.sets.filter { $0.displayKey == key }.sorted { $0.lastUsed > $1.lastUsed }
        return sets.map { set in
            Context(screen: screen, area: area, grid: set.grid, setID: set.id, members: Set(set.members.map(\.windowID)))
        } + [Context(screen: screen, area: area, grid: settings.grid(for: screen), setID: nil, members: nil)]
    }

    private func updateHover(at point: CGPoint, scope: TileGrid.Scope, force: Bool = false) {
        guard session == nil else { return }
        guard let screen = Screen.containing(point) else { return clearHover() }

        // First the cheap check, whether the pointer is in a gap of any candidate grid at all.
        let candidates = contexts(on: screen).compactMap { context in
            context.grid.divider(at: point, in: context.area, gap: settings.gap, scope: scope).map { (context, $0) }
        }
        guard !candidates.isEmpty else { return clearHover() }

        if force || hover.map({ previous in !candidates.contains { $0.0.setID == previous.context.setID && $0.1 == previous.divider } }) ?? true {
            let onScreen = WindowList.onScreen()
            let topIndex = onScreen.firstIndex { $0.bounds.contains(point) }
            hover = nil
            for (context, divider) in candidates {
                let tiled = tiledWindows(in: context.grid.cells(beside: divider), of: context, onScreen: onScreen)
                // A window in front of the tiled ones keeps its clicks; one behind the grid, showing
                // through the gap, doesn't count.
                let frontTiled = tiled.compactMap { item in onScreen.firstIndex { $0.id == item.info.id } }.min()
                if let frontTiled, topIndex.map({ $0 >= frontTiled }) ?? true {
                    hover = Hover(context: context, divider: divider, isLive: true)
                    break
                }
            }
        } else if let previous = hover, let match = candidates.first(where: { $0.0.setID == previous.context.setID }) {
            hover = Hover(context: previous.context, divider: match.1, isLive: previous.isLive)
        }

        if let hover, hover.isLive {
            overlay.showHandle(hover.context.grid.frame(of: hover.divider, in: hover.context.area, gap: settings.gap, minimumThickness: 8),
                               on: screen, active: false, spansLine: scope == .line)
        } else {
            overlay.hideHandle()
        }
    }

    private func clearHover() {
        guard hover != nil else { return }
        hover = nil
        overlay.hideHandle()
    }

    // MARK: Drag

    private func begin(at point: CGPoint, scope: TileGrid.Scope) -> Bool {
        guard let hover, hover.isLive else { return false }
        let context = hover.context
        let grid = context.grid
        guard let divider = grid.divider(at: point, in: context.area, gap: settings.gap, scope: scope),
              let line = grid.divider(at: point, in: context.area, gap: settings.gap, scope: .line) else { return false }

        var resolver = AXWindow.Resolver()
        let windows: [(window: AXWindow, cell: Int)] = tiledWindows(in: grid.cells(beside: line), of: context, onScreen: WindowList.onScreen())
            .compactMap { item in resolver.window(item.info.id, pid: item.info.pid).map { ($0, item.cell) } }
        guard !windows.isEmpty else { return false }

        let gapFrame = grid.frame(of: divider, in: context.area, gap: settings.gap)
        let center = divider.axis == .vertical ? gapFrame.midX : gapFrame.midY
        let grabOffset = (divider.axis == .vertical ? point.x : point.y) - center
        let session = Session(context: context, start: point, grabOffset: grabOffset, windows: windows, grid: grid,
                              divider: divider, scope: scope, position: center)
        self.session = session
        overlay.beginResize(standIns(for: session), on: context.screen)
        overlay.showHandle(grid.frame(of: divider, in: context.area, gap: settings.gap, minimumThickness: 8),
                           on: context.screen, active: true, spansLine: scope == .line)
        return true
    }

    private func drag(to point: CGPoint, scope: TileGrid.Scope) {
        guard var session else { return }
        let context = session.context
        // Recomputed from the grid as it was at mouse-down, so switching scope mid-drag puts
        // whatever the other scope had moved back where it was.
        guard let divider = context.grid.divider(at: session.start, in: context.area, gap: settings.gap, scope: scope) else { return }
        let position = (divider.axis == .vertical ? point.x : point.y) - session.grabOffset
        var grid = context.grid
        let snapped = grid.move(divider, to: position, in: context.area, gap: settings.gap,
                                minimums: Self.minimums(of: session.windows), snap: Self.snapDistance)
        if snapped, !session.snapped {
            // The same alignment tick macOS gives when objects line up in Keynote or Freeform.
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        session.grid = grid
        session.divider = divider
        session.scope = scope
        session.position = position
        session.snapped = snapped
        self.session = session

        let gapFrame = grid.frame(of: divider, in: context.area, gap: settings.gap, minimumThickness: 8)
        overlay.updateResize(standIns(for: session), handle: gapFrame, spansLine: scope == .line, on: context.screen)
        if snapped {
            // A hairline across the whole area, along the edge it lined up with.
            let guide = divider.axis == .vertical
                ? CGRect(x: gapFrame.midX - 1, y: context.area.minY, width: 2, height: context.area.height)
                : CGRect(x: context.area.minX, y: gapFrame.midY - 1, width: context.area.width, height: 2)
            overlay.showGuide(guide)
        } else {
            overlay.hideGuide()
        }
    }

    @discardableResult
    private func end() -> Task<Void, Never>? {
        guard let session else { return nil }
        self.session = nil
        hover = nil
        overlay.hideGuide()
        save(session)
        let known = Self.minimums(of: session.windows)
        return Task {
            await Tiler.perform(moves(for: session))
            // A window that wouldn't shrink as far as asked has shown its minimum size, so the
            // gap goes back to where it fits. Later drags stop there by themselves.
            let minimums = Self.minimums(of: session.windows)
            if minimums != known {
                var fitted = session
                fitted.grid = session.context.grid
                fitted.grid.move(session.divider, to: session.position, in: session.context.area, gap: settings.gap,
                                 minimums: minimums, snap: Self.snapDistance)
                save(fitted)
                let gapFrame = fitted.grid.frame(of: fitted.divider, in: fitted.context.area, gap: settings.gap, minimumThickness: 8)
                overlay.updateResize(standIns(for: fitted), handle: gapFrame, spansLine: fitted.scope == .line, on: fitted.context.screen)
                await Tiler.perform(moves(for: fitted))
            }
            overlay.endResize()
        }
    }

    private func save(_ session: Session) {
        settings.setGrid(session.grid, for: session.context.screen)
        if let id = session.context.setID {
            settings.library.updateGrid(session.grid, ofSet: id)
            settings.library.touch(id, at: .now)
        }
    }

    /// The windows the current scope resizes, with their new frames.
    private func moves(for session: Session) -> [Tiler.Move] {
        let cells = session.grid.cellFrames(in: session.context.area, gap: settings.gap)
        let moving = Set(session.grid.cells(beside: session.divider))
        return session.windows.filter { moving.contains($0.cell) }.map { Tiler.Move(window: $0.window, frame: cells[$0.cell]) }
    }

    /// Frosted stand-ins for the windows the current scope resizes.
    private func standIns(for session: Session) -> [(frame: CGRect, icon: NSImage?)] {
        moves(for: session).map { ($0.frame, Tiler.icon($0.window.pid)) }
    }

    /// The smallest size each cell's window accepts, where it is known.
    private static func minimums(of windows: [(window: AXWindow, cell: Int)]) -> [Int: CGSize] {
        Dictionary(windows.compactMap { item in MinimumSizes[item.window.windowID].map { (item.cell, $0) } },
                   uniquingKeysWith: { first, _ in first })
    }

    // MARK: Windows

    /// Windows sitting in the given cells, front-most first. With a set, only its members count.
    private func tiledWindows(in cellIndices: [Int], of context: Context, onScreen: [WindowInfo]) -> [(info: WindowInfo, cell: Int)] {
        let cells = context.grid.cellFrames(in: context.area, gap: settings.gap)
        let wanted = Set(cellIndices)
        let windows = onScreen.filter { window in
            context.screen.axFrame.contains(window.bounds.center) && (context.members?.contains(window.id) ?? true)
        }
        var claimed = Set<Int>()
        return zip(windows, GridMath.match(windows: windows.map(\.bounds), to: cells)).compactMap { info, cell in
            // Only the front-most window in each cell moves; ones hidden behind it stay put.
            guard let cell, wanted.contains(cell), claimed.insert(cell).inserted else { return nil }
            return (info, cell)
        }
    }
}

private nonisolated func gapTapCallback(_: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    // Raw pointers aren't Sendable; the address crosses into the main actor as an integer.
    let address = UInt(bitPattern: refcon)
    let location = event.location
    let shift = event.flags.contains(.maskShift)
    // The tap's run loop source is on the main run loop.
    let swallow = MainActor.assumeIsolated { () -> Bool in
        guard let pointer = UnsafeRawPointer(bitPattern: address) else { return false }
        let controller = Unmanaged<GapController>.fromOpaque(pointer).takeUnretainedValue()
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            controller.reenable()
            return false
        }
        return controller.handle(type, at: location, shift: shift)
    }
    return swallow ? nil : Unmanaged.passUnretained(event)
}

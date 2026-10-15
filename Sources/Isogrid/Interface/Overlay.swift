import AppKit
import QuartzCore

/// The full-screen, click-through layer above all windows. It draws the grid, the glass drop
/// target, the gap handle, and the frosted stand-ins that hide windows while they move.
final class Overlay {
    struct Flight {
        let from: CGRect
        let to: CGRect
        let icon: NSImage?
    }

    private let panel: NSPanel
    private let container = FlippedView()
    private let frost = FrostView()
    private let grid = GridView()
    private let target = GlassPane(kind: .target)
    private let handle = GlassPane(kind: .handle)
    private let guide = NSView()
    private var standIns: [GlassPane] = []
    /// The cell the swap preview starts from, while one is showing.
    private var swapOrigin: CGRect?
    private let animator: Animator
    private var screen: NSScreen?
    private var targetIndex: Int?
    private var generation = 0

    private var reduceMotion: Bool { animator.reduceMotion }

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        // Above the menu bar, so the frost hides apps switching there too; below the picker.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.contentView = container
        animator = Animator(host: container)

        for view in [frost, grid, target, guide, handle] as [NSView] {
            view.alphaValue = 0
            container.addSubview(view)
        }
        guide.wantsLayer = true
        guide.layer?.cornerRadius = 1
        frost.autoresizingMask = [.width, .height]
        grid.autoresizingMask = [.width, .height]
    }

    // MARK: Drag to a cell

    func track(cells: [CGRect], target index: Int, on screen: NSScreen) {
        let moved = place(on: screen)
        let local = cells.map(local)
        grid.setCells(local)
        target.setFrosted(false)

        if target.alphaValue == 0 || moved {
            animator.set(target, inset(local[index]))
            show()
            fade([grid, target], to: 1, duration: 0.16)
        } else if index != targetIndex {
            animator.animate(target, to: inset(local[index]), with: .track)
        }
        targetIndex = index
    }

    func previewSwap(from: CGRect, to: CGRect, icon: NSImage?) {
        let pane = standIns(count: 1)[0]
        if swapOrigin != from || pane.alphaValue == 0 {
            animator.set(pane, local(from))
            pane.setIcon(icon)
            fade([pane], to: 1, duration: 0.12)
        }
        swapOrigin = from
        animator.animate(pane, to: local(to), with: .track)
    }

    /// The preview glides back into its cell and fades as the pointer leaves it.
    func clearSwap() {
        guard let origin = swapOrigin, let pane = standIns.first else { return }
        swapOrigin = nil
        animator.animate(pane, to: local(origin), with: .track)
        fade([pane], to: 0, duration: 0.18)
    }

    /// The target frosts over so the window snapping into the cell happens out of sight.
    func beginDrop() {
        target.setFrosted(true)
        fade([grid], to: 0, duration: 0.12)
    }

    func endDrop() {
        hideAll(duration: 0.28)
    }

    func cancel() {
        guard panel.isVisible else { return }
        hideAll(duration: 0.14)
    }

    // MARK: Picker preview

    /// Shown instantly, because the picker is keyboard-driven and motion there would read as delay.
    func preview(cells: [CGRect], on screen: NSScreen) {
        place(on: screen)
        grid.setCells(cells.map(local))
        show()
        grid.alphaValue = 1
        target.alphaValue = 0
        targetIndex = nil
    }

    // MARK: Tiling

    /// Frosts the screen, then flies a glass stand-in from each window's current frame to its
    /// cell. The real windows move behind the frost, so their resizing never shows.
    func beginTransition(_ flights: [Flight], on screen: NSScreen) {
        place(on: screen)
        show()
        target.alphaValue = 0
        handle.alphaValue = 0
        targetIndex = nil
        let panes = standIns(count: flights.count)
        for (pane, flight) in zip(panes, flights) {
            animator.set(pane, local(flight.from))
            pane.setIcon(flight.icon)
            pane.alphaValue = 0
            animator.animate(pane, to: local(flight.to), with: .fly)
        }
        fade([frost] + panes, to: 1, duration: 0.12)
        fade([grid], to: 0, duration: 0.12)
    }

    /// Waits for the stand-ins to land, then dissolves the frost to reveal the windows.
    func endTransition() async {
        await animator.settled()
        hideAll(duration: 0.3)
    }

    // MARK: Gap resizing

    /// `spansLine` stretches the handle along the whole gap, showing that the drag moves the line.
    func showHandle(_ frame: CGRect, on screen: NSScreen, active: Bool, spansLine: Bool) {
        let moved = place(on: screen)
        let local = handleFrame(around: local(frame), active: active, spansLine: spansLine)
        handle.cornerRadius = min(local.width, local.height) / 2
        if handle.alphaValue == 0 || moved {
            animator.set(handle, local)
            show()
            fade([handle], to: 1, duration: 0.14)
        } else {
            animator.animate(handle, to: local, with: .track)
        }
    }

    func hideHandle() {
        guard handle.alphaValue > 0 else { return }
        fade([handle], to: 0, duration: 0.14) { [weak self] in self?.orderOutIfIdle() }
    }

    /// Frosted stand-ins cover the windows being resized and follow the pointer 1:1.
    /// The windows themselves resize once, on release, behind them.
    func beginResize(_ panes: [(frame: CGRect, icon: NSImage?)], on screen: NSScreen) {
        place(on: screen)
        show()
        for (pane, item) in zip(standIns(count: panes.count), panes) {
            animator.set(pane, local(item.frame))
            pane.setIcon(item.icon)
            pane.alphaValue = 0
            fade([pane], to: 1, duration: 0.12)
        }
    }

    func updateResize(_ panes: [(frame: CGRect, icon: NSImage?)], handle frame: CGRect, spansLine: Bool, on screen: NSScreen) {
        // Switching scope mid-drag changes how many windows move; panes for the others go away.
        for (pane, item) in zip(standIns(count: panes.count), panes) {
            animator.set(pane, local(item.frame))
            pane.setIcon(item.icon)
            pane.alphaValue = 1
        }
        animator.set(handle, handleFrame(around: local(frame), active: true, spansLine: spansLine))
    }

    /// An alignment line along the edge a dragged gap snapped to.
    func showGuide(_ frame: CGRect) {
        guide.frame = local(frame)
        guide.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.85).cgColor
        guide.layer?.shadowColor = NSColor.controlAccentColor.cgColor
        guide.layer?.shadowOpacity = 0.6
        guide.layer?.shadowRadius = 6
        guide.layer?.shadowOffset = .zero
        if guide.alphaValue == 0 { fade([guide], to: 1, duration: 0.1) }
    }

    func hideGuide() {
        guard guide.alphaValue > 0 else { return }
        fade([guide], to: 0, duration: 0.12)
    }

    func endResize() {
        hideAll(duration: 0.26)
    }

    // MARK: Plumbing

    @discardableResult
    private func place(on screen: NSScreen) -> Bool {
        guard screen != self.screen else { return false }
        self.screen = screen
        panel.setFrame(screen.frame, display: false)
        return true
    }

    private func local(_ rect: CGRect) -> CGRect {
        guard let origin = screen?.axFrame.origin else { return rect }
        return rect.offsetBy(dx: -origin.x, dy: -origin.y)
    }

    /// The target sits a hair inside the cell so its glow reads as belonging to the cell.
    private func inset(_ rect: CGRect) -> CGRect { rect.insetBy(dx: 2, dy: 2) }

    /// A capsule centred on the gap at the pointer, longer while it is being dragged, or
    /// running the length of the gap when the whole line moves.
    private func handleFrame(around gap: CGRect, active: Bool, spansLine: Bool) -> CGRect {
        let pointer = local(CGRect(origin: Screen.mouse, size: .zero)).origin
        let thickness: CGFloat = active ? 7 : 6
        let along = max(gap.width, gap.height)
        let length: CGFloat = spansLine ? max(along - 24, 64) : min(active ? 96 : 64, along)
        if gap.height > gap.width {
            let y = min(max(pointer.y - length / 2, gap.minY), gap.maxY - length)
            return CGRect(x: gap.midX - thickness / 2, y: y, width: thickness, height: length)
        } else {
            let x = min(max(pointer.x - length / 2, gap.minX), gap.maxX - length)
            return CGRect(x: x, y: gap.midY - thickness / 2, width: length, height: thickness)
        }
    }

    private func standIns(count: Int) -> [GlassPane] {
        while standIns.count < count {
            let pane = GlassPane(kind: .standIn)
            pane.alphaValue = 0
            container.addSubview(pane, positioned: .below, relativeTo: target)
            standIns.append(pane)
        }
        for pane in standIns.dropFirst(count) { pane.alphaValue = 0 }
        return Array(standIns.prefix(count))
    }

    private func show() {
        generation += 1
        panel.orderFrontRegardless()
    }

    private func hideAll(duration: TimeInterval) {
        generation += 1
        let generation = generation
        targetIndex = nil
        swapOrigin = nil
        let duration = reduceMotion ? min(duration, 0.15) : duration
        fade([frost, grid, target, guide, handle] + standIns, to: 0, duration: duration)
        // Removal runs on a timer, never on an animation's completion, so the panel can't be
        // left on screen if an animation is interrupted.
        Task {
            try? await Task.sleep(for: .seconds(duration + 0.02))
            guard self.generation == generation else { return }
            panel.orderOut(nil)
            target.setFrosted(false)
        }
    }

    private func orderOutIfIdle() {
        let views: [NSView] = [frost, grid, target, guide, handle] + standIns
        if views.allSatisfy({ $0.alphaValue == 0 }) { panel.orderOut(nil) }
    }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// A full-screen blur with a soft vignette, used as a curtain while windows rearrange.
private final class FrostView: NSView {
    private let blur = NSVisualEffectView()
    private let vignette = CAGradientLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        blur.material = .fullScreenUI
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.autoresizingMask = [.width, .height]
        addSubview(blur)
        wantsLayer = true
        vignette.type = .radial
        vignette.startPoint = CGPoint(x: 0.5, y: 0.5)
        vignette.endPoint = CGPoint(x: 1.1, y: 1.1)
        vignette.colors = [NSColor.black.withAlphaComponent(0).cgColor, NSColor.black.withAlphaComponent(0.3).cgColor]
        layer?.addSublayer(vignette)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        vignette.frame = bounds
        CATransaction.commit()
    }
}

/// Grid cells drawn as hairline outlines over a faint fill, both lighter at the top.
private final class GridView: NSView {
    private var cells: [CALayer] = []
    private static let radius: CGFloat = 16

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func setCells(_ frames: [CGRect]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        while cells.count < frames.count {
            let cell = makeCell()
            layer?.addSublayer(cell)
            cells.append(cell)
        }
        for (i, cell) in cells.enumerated() {
            cell.isHidden = i >= frames.count
            guard i < frames.count else { continue }
            cell.frame = frames[i]
            for sublayer in cell.sublayers ?? [] {
                sublayer.frame = cell.bounds
                if let mask = sublayer.mask as? CAShapeLayer {
                    mask.frame = cell.bounds
                    mask.path = CGPath(roundedRect: cell.bounds.insetBy(dx: 0.5, dy: 0.5), cornerWidth: Self.radius,
                                       cornerHeight: Self.radius, transform: nil)
                }
            }
            cell.shadowPath = CGPath(roundedRect: cell.bounds, cornerWidth: Self.radius, cornerHeight: Self.radius, transform: nil)
        }
        CATransaction.commit()
    }

    private func makeCell() -> CALayer {
        let cell = CALayer()
        cell.cornerRadius = Self.radius
        cell.cornerCurve = .continuous
        cell.masksToBounds = false
        // A dark one-point halo keeps the outline legible over bright windows.
        cell.shadowColor = NSColor.black.cgColor
        cell.shadowOpacity = 0.3
        cell.shadowRadius = 1.5
        cell.shadowOffset = .zero

        let fill = CAGradientLayer()
        fill.cornerRadius = Self.radius
        fill.cornerCurve = .continuous
        fill.colors = [NSColor.white.withAlphaComponent(0.10).cgColor, NSColor.white.withAlphaComponent(0.03).cgColor]
        fill.startPoint = CGPoint(x: 0.5, y: 0)
        fill.endPoint = CGPoint(x: 0.5, y: 1)
        cell.addSublayer(fill)

        let rim = CAGradientLayer()
        rim.colors = [NSColor.white.withAlphaComponent(0.75).cgColor, NSColor.white.withAlphaComponent(0.25).cgColor]
        rim.startPoint = CGPoint(x: 0.5, y: 0)
        rim.endPoint = CGPoint(x: 0.5, y: 1)
        let stroke = CAShapeLayer()
        stroke.fillColor = nil
        stroke.strokeColor = NSColor.black.cgColor
        stroke.lineWidth = 1
        rim.mask = stroke
        cell.addSublayer(rim)
        return cell
    }
}

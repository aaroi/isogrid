import AppKit
import IsogridCore
import SwiftUI

// MARK: Model

@Observable
final class PickerModel {
    let presets = TileLayout.presets
    private(set) var selection = 0
    private(set) var sets: [SetSummary] = []
    enum Row { case layouts, sets }
    private(set) var row = Row.layouts
    private(set) var setSelection = 0
    private(set) var typedRows: Int?
    private(set) var current = TileLayout.default

    var gap: CGFloat = 8

    @ObservationIgnored var onSelect: (TileLayout) -> Void = { _ in }
    @ObservationIgnored var onApply: (TileLayout) -> Void = { _ in }
    @ObservationIgnored var onSelectSet: (SetSummary) -> Void = { _ in }
    @ObservationIgnored var onRecall: (Int) -> Void = { _ in }

    var selected: TileLayout { presets[selection] }

    func reset(current: TileLayout, sets: [SetSummary]) {
        self.current = current
        self.sets = sets
        selection = presets.firstIndex(of: current) ?? 0
        typedRows = nil
        row = .layouts
        setSelection = 0
    }

    func select(_ index: Int) {
        guard presets.indices.contains(index), index != selection || row != .layouts else { return }
        row = .layouts
        selection = index
        onSelect(selected)
    }

    func selectSet(_ index: Int) {
        guard sets.indices.contains(index), index != setSelection || row != .sets else { return }
        row = .sets
        setSelection = index
        onSelectSet(sets[index])
    }

    func move(by offset: Int) {
        if row == .layouts {
            select(min(max(selection + offset, 0), presets.count - 1))
        } else {
            selectSet(min(max(setSelection + offset, 0), sets.count - 1))
        }
    }

    func moveRow(by offset: Int) {
        if offset > 0, row == .layouts, !sets.isEmpty {
            selectSet(min(setSelection, sets.count - 1))
        } else if offset < 0, row == .sets {
            select(selection)
        }
    }

    /// The first digit picks rows and jumps to the first matching preset; the second picks
    /// columns and applies immediately, so any grid up to 6×8 is two keystrokes away.
    func type(_ digit: Int) {
        if let rows = typedRows {
            typedRows = nil
            if let layout = TileLayout(rows: rows, columns: digit) { onApply(layout) }
        } else if (1...TileLayout.maxRows).contains(digit) {
            typedRows = digit
            if let index = presets.firstIndex(where: { $0.rows == digit }) { select(index) }
        }
    }

    func clearTyping() {
        typedRows = nil
    }

    func apply() {
        if row == .sets, sets.indices.contains(setSelection) {
            onRecall(sets[setSelection].slot)
        } else {
            onApply(selected)
        }
    }

    func apply(_ index: Int) {
        guard presets.indices.contains(index) else { return }
        onApply(presets[index])
    }
}

// MARK: Views

struct PickerView: View {
    let model: PickerModel

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 4) {
                ForEach(Array(model.presets.enumerated()), id: \.offset) { index, layout in
                    LayoutTile(
                        layout: layout,
                        isSelected: model.row == .layouts && index == model.selection,
                        isCurrent: layout == model.current,
                        isDimmed: model.typedRows.map { $0 != layout.rows } ?? false
                    )
                    .onHover { if $0 { model.select(index) } }
                    .onTapGesture { model.apply(index) }
                }
            }
            if !model.sets.isEmpty {
                Rectangle().fill(.primary.opacity(0.08)).frame(height: 1).padding(.horizontal, 8)
                HStack(spacing: 4) {
                    ForEach(Array(model.sets.enumerated()), id: \.element.id) { index, set in
                        SetTile(set: set, isSelected: model.row == .sets && index == model.setSelection)
                            .onHover { if $0 { model.selectSet(index) } }
                            .onTapGesture { model.onRecall(set.slot) }
                    }
                    Spacer(minLength: 0)
                }
            }
            Footer(typedRows: model.typedRows, gap: model.gap, action: model.row == .sets ? "Show" : "Tile")
        }
        .padding(10)
        .modifier(PanelSurface())
        .padding(24) // room for the panel shadow
    }
}

private struct LayoutTile: View {
    let layout: TileLayout
    let isSelected: Bool
    let isCurrent: Bool
    let isDimmed: Bool

    var body: some View {
        VStack(spacing: 7) {
            GridGlyph(layout: layout, isSelected: isSelected)
                .frame(width: 64, height: 40)
            HStack(spacing: 4) {
                Text(layout.name)
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? .primary : .secondary)
                if isCurrent {
                    Circle().fill(Color.accentColor).frame(width: 4, height: 4)
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.primary.opacity(isSelected ? 0.08 : 0))
        }
        .opacity(isDimmed ? 0.3 : 1)
        .contentShape(Rectangle())
    }
}

private struct SetTile: View {
    let set: SetSummary
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 7) {
            SetGlyph(set: set, isSelected: isSelected)
                .frame(width: 64, height: 40)
            VStack(spacing: 3) {
                Text("⌃⌥\(set.slot)")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(.primary.opacity(0.08)))
                Text(set.title)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 64)
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .padding(.horizontal, 9)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.primary.opacity(isSelected ? 0.08 : 0))
        }
        .contentShape(Rectangle())
        .help(set.title)
    }
}

/// A set's grid with each window's app icon in its cell.
struct SetGlyph: View {
    let set: SetSummary
    var isSelected = false

    var body: some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            context.stroke(Path(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 7, style: .continuous),
                           with: .color(isSelected ? .accentColor : .primary.opacity(0.18)), lineWidth: 1)
            for (index, cell) in set.grid.cellFrames(in: bounds, gap: 3).enumerated() {
                context.fill(Path(roundedRect: cell, cornerRadius: 3, style: .continuous), with: .color(.primary.opacity(0.12)))
                guard let icon = set.icons[index] else { continue }
                let side = min(min(cell.width, cell.height) - 2, 18)
                let rect = CGRect(x: cell.midX - side / 2, y: cell.midY - side / 2, width: side, height: side)
                context.draw(context.resolve(Image(nsImage: icon)), in: rect)
            }
        }
    }
}

/// A miniature display with the layout's cells drawn in it.
struct GridGlyph: View {
    let layout: TileLayout
    var isSelected = false

    var body: some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            context.stroke(Path(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 7, style: .continuous),
                           with: .color(.primary.opacity(0.18)), lineWidth: 1)
            let fill: GraphicsContext.Shading = isSelected ? .color(.accentColor) : .color(.primary.opacity(0.24))
            for cell in layout.cellFrames(in: bounds, gap: 3) {
                context.fill(Path(roundedRect: cell, cornerRadius: 3, style: .continuous), with: fill)
            }
        }
    }
}

private struct Footer: View {
    let typedRows: Int?
    let gap: CGFloat
    let action: String

    var body: some View {
        HStack(spacing: 14) {
            if let typedRows {
                Text("\(typedRows) × ").foregroundStyle(.primary) + Text("columns").foregroundStyle(.tertiary)
            } else {
                Text("Type rows, then columns")
            }
            Spacer(minLength: 20)
            KeyHint(key: "[ ]", label: "Gap \(Int(gap))")
            KeyHint(key: "↩", label: action)
            KeyHint(key: "esc", label: "Close")
        }
        .font(.system(size: 11))
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.bottom, 2)
    }
}

private struct KeyHint: View {
    let key: String
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Text(key)
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(.primary.opacity(0.08)))
            Text(label)
        }
    }
}

struct PanelSurface: ViewModifier {
    #if DEBUG
    /// ImageRenderer cannot draw glass or materials, so snapshots use a solid surface.
    nonisolated(unsafe) static var isSnapshot = false
    #else
    static let isSnapshot = false
    #endif
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        if Self.isSnapshot {
            content
                .background(Color(nsColor: .windowBackgroundColor), in: shape)
                .overlay(shape.strokeBorder(.primary.opacity(0.1)))
        } else if #available(macOS 26, *), !reduceTransparency {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(reduceTransparency ? AnyShapeStyle(.background) : AnyShapeStyle(.regularMaterial), in: shape)
                .overlay(shape.strokeBorder(.primary.opacity(0.1)))
                .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
        }
    }
}

// MARK: Panel

private final class PickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// The ⌥G layout picker. It opens and closes without animation, because it's a shortcut
/// used many times a day and any motion would read as delay.
final class PickerController: NSObject, NSWindowDelegate {
    private let model = PickerModel()
    private let overlay: Overlay
    private let tiler: Tiler
    private let settings = Settings.shared
    private var panel: PickerPanel?
    private var keyMonitor: Any?
    private var screen: NSScreen?

    var onLayoutChange: () -> Void = {}

    init(overlay: Overlay, tiler: Tiler) {
        self.overlay = overlay
        self.tiler = tiler
        super.init()
        model.onSelect = { [weak self] layout in self?.preview(layout) }
        model.onApply = { [weak self] layout in self?.apply(layout) }
        model.onSelectSet = { [weak self] set in self?.preview(set.grid) }
        model.onRecall = { [weak self] slot in
            self?.close()
            self?.tiler.recall(slot: slot)
        }
    }

    var isOpen: Bool { keyMonitor != nil }

    func toggle() {
        isOpen ? close() : open()
    }

    func open() {
        guard !isOpen, let screen = Screen.underMouse else { return }
        self.screen = screen
        let current = settings.layout(for: screen)
        tiler.pruneClosedWindows()
        model.reset(current: current, sets: settings.library.sets.sorted { $0.slot < $1.slot }.map(SetSummary.init))
        model.gap = settings.gap

        let panel = self.panel ?? makePanel()
        self.panel = panel
        let size = panel.contentView?.fittingSize ?? .zero
        let area = screen.visibleFrame
        // Upper third, where Spotlight sits.
        panel.setFrame(CGRect(x: (area.midX - size.width / 2).rounded(), y: (area.minY + area.height * 0.64 - size.height / 2).rounded(),
                              width: size.width, height: size.height), display: true)

        preview(model.presets.contains(current) ? model.selected : current)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
            return nil
        }
        panel.makeKeyAndOrderFront(nil)
    }

    func close(keepingOverlay: Bool = false) {
        guard let keyMonitor else { return }
        NSEvent.removeMonitor(keyMonitor)
        self.keyMonitor = nil
        panel?.orderOut(nil)
        if !keepingOverlay { overlay.cancel() }
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    private func handle(_ event: NSEvent) {
        switch Int(event.keyCode) {
        case kVK.escape: model.typedRows == nil ? close() : model.clearTyping()
        case kVK.return, kVK.enter: model.apply()
        case kVK.left: model.move(by: -1)
        case kVK.right: model.move(by: 1)
        case kVK.up: model.moveRow(by: -1)
        case kVK.down: model.moveRow(by: 1)
        case kVK.delete: model.clearTyping()
        case kVK.leftBracket: adjustGap(by: -2)
        case kVK.rightBracket: adjustGap(by: 2)
        default:
            if let digit = event.charactersIgnoringModifiers?.first?.wholeNumberValue { model.type(digit) }
        }
    }

    /// Spacing changes preview live; Return applies them with the layout.
    private func adjustGap(by delta: CGFloat) {
        settings.setGap(settings.gap + delta)
        model.gap = settings.gap
        preview(model.selected)
    }

    private func preview(_ layout: TileLayout) {
        preview(TileGrid(layout))
    }

    private func preview(_ grid: TileGrid) {
        guard let screen else { return }
        overlay.preview(cells: grid.cellFrames(in: screen.axVisibleFrame, gap: settings.gap), on: screen)
    }

    private func apply(_ layout: TileLayout) {
        guard let screen else { return }
        close(keepingOverlay: true)
        tiler.apply(layout, on: screen)
        onLayoutChange()
    }

    private func makePanel() -> PickerPanel {
        let panel = PickerPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: PickerView(model: model))
        return panel
    }
}

private enum kVK {
    static let `return` = 0x24
    static let enter = 0x4C
    static let escape = 0x35
    static let delete = 0x33
    static let left = 0x7B
    static let right = 0x7C
    static let down = 0x7D
    static let up = 0x7E
    static let leftBracket = 0x21
    static let rightBracket = 0x1E
}

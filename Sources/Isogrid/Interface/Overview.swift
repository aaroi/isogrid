import AppKit
import Carbon.HIToolbox
import IsogridCore
import SwiftUI

// MARK: Model

struct OverviewCard: Identifiable {
    let slot: Int
    let grid: TileGrid
    let title: String
    /// Cell index to the window in it.
    let windows: [Int: CGWindowID]
    let icons: [Int: NSImage]
    /// Width over height of the set's display.
    let aspect: CGFloat
    let gap: CGFloat
    var id: Int { slot }
}

@Observable
final class OverviewModel {
    private(set) var cards: [OverviewCard] = []
    private(set) var selection = 0
    var thumbnails: [CGWindowID: NSImage] = [:]
    var previewsAllowed = false
    /// The picked card, which lifts slightly while everything else fades.
    var picked: Int?
    var appeared = false

    @ObservationIgnored var onPick: (Int) -> Void = { _ in }
    @ObservationIgnored var onAllowPreviews: () -> Void = {}
    @ObservationIgnored var onDismiss: () -> Void = {}

    func reset(cards: [OverviewCard]) {
        self.cards = cards
        selection = 0
        picked = nil
        appeared = false
    }

    func select(_ index: Int) {
        guard cards.indices.contains(index) else { return }
        selection = index
    }

    func move(by offset: Int) {
        select(min(max(selection + offset, 0), cards.count - 1))
    }

    func pick() {
        guard cards.indices.contains(selection) else { return }
        onPick(cards[selection].slot)
    }
}

// MARK: Views

struct OverviewView: View {
    let model: OverviewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if model.cards.isEmpty {
                    EmptyOverview()
                } else {
                    cards(in: geometry.size)
                }
                VStack {
                    Spacer()
                    OverviewFooter(previewsAllowed: model.previewsAllowed, allow: model.onAllowPreviews)
                        .opacity(model.picked == nil ? 1 : 0)
                }
                .padding(.bottom, 28)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            // A click anywhere outside the cards closes the overview.
            .background(Color.black.opacity(0.001).onTapGesture { model.onDismiss() })
        }
        .opacity(model.appeared ? 1 : 0)
        .scaleEffect(model.appeared || reduceMotion ? 1 : 0.97)
    }

    private func cards(in size: CGSize) -> some View {
        let count = model.cards.count
        let columns = count <= 3 ? count : (count == 4 ? 2 : 3)
        let rows = Int(ceil(Double(count) / Double(columns)))
        let spacing: CGFloat = 36
        let aspect = model.cards.first?.aspect ?? 16 / 10
        let byWidth = (size.width - 160 - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        let byHeight = ((size.height - 220 - spacing * CGFloat(rows - 1)) / CGFloat(rows) - 34) * aspect
        let width = min(byWidth, byHeight, 640)

        return VStack(spacing: spacing) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(row * columns..<min(row * columns + columns, count), id: \.self) { index in
                        card(index, width: width, in: size)
                    }
                }
            }
        }
    }

    private func card(_ index: Int, width: CGFloat, in size: CGSize) -> some View {
        let card = model.cards[index]
        let isPicked = model.picked == card.slot

        return CardView(card: card, width: width, thumbnails: model.thumbnails, isSelected: index == model.selection && model.picked == nil)
            .scaleEffect(isPicked ? 1.04 : 1)
            .opacity(model.picked == nil || isPicked ? 1 : 0)
            .zIndex(isPicked ? 1 : 0)
            .onHover { if $0 { model.select(index) } }
            .onTapGesture {
                model.select(index)
                model.pick()
            }
    }
}

private struct CardView: View {
    let card: OverviewCard
    let width: CGFloat
    let thumbnails: [CGWindowID: NSImage]
    let isSelected: Bool

    var body: some View {
        let height = width / card.aspect
        VStack(spacing: 10) {
            Color.clear
                .frame(width: width, height: height)
                .overlay(alignment: .topLeading) { cells(width: width, height: height) }
                .background(
                    LinearGradient(colors: [.white.opacity(0.10), .white.opacity(0.03)], startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : .white.opacity(0.18), lineWidth: isSelected ? 2.5 : 1)
                }
                .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
            HStack(spacing: 8) {
                Text("⌃⌥\(card.slot)")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.white.opacity(0.14)))
                Text(card.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(.white.opacity(isSelected ? 1 : 0.75))
            .frame(maxWidth: width)
        }
        .scaleEffect(isSelected ? 1.02 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isSelected)
        .contentShape(Rectangle())
    }

    private func cells(width: CGFloat, height: CGFloat) -> some View {
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let frames = card.grid.cellFrames(in: bounds, gap: max(3, card.gap * width / 1500))
        return ZStack(alignment: .topLeading) {
            ForEach(frames.indices, id: \.self) { index in
                let frame = frames[index]
                cell(index, size: frame.size)
                    .frame(width: frame.width, height: frame.height)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .offset(x: frame.minX, y: frame.minY)
            }
        }
    }

    @ViewBuilder
    private func cell(_ index: Int, size: CGSize) -> some View {
        if let id = card.windows[index], let image = thumbnails[id] {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size.width, height: size.height, alignment: .top)
        } else {
            ZStack {
                Rectangle().fill(.white.opacity(card.windows[index] == nil ? 0.04 : 0.09))
                if let icon = card.icons[index] {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: min(min(size.width, size.height) * 0.42, 56), height: min(min(size.width, size.height) * 0.42, 56))
                        .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                }
            }
        }
    }
}

private struct EmptyOverview: View {
    var body: some View {
        VStack(spacing: 10) {
            GridGlyph(layout: .default)
                .frame(width: 96, height: 60)
                .foregroundStyle(.white)
            Text("No sets yet")
                .font(.system(size: 17, weight: .semibold))
            Text("Tile some windows with Option-G and they show up here.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.7))
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }
}

private struct OverviewFooter: View {
    let previewsAllowed: Bool
    let allow: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            hint("←→", "Choose")
            hint("↩", "Show")
            hint("1–9", "Jump")
            hint("esc", "Close")
            if !previewsAllowed {
                Button(action: allow) {
                    Text("Show window previews…")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(.white.opacity(0.16)))
                }
                .buttonStyle(.plain)
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(.white.opacity(0.75))
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 6) {
            Text(key)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.white.opacity(0.14)))
            Text(label)
        }
    }
}

// MARK: Controller

private final class OverviewPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Control-Option-Space shows every set as one card. Picking a card brings its set forward behind
/// the overview, which then fades away.
final class OverviewController: NSObject, NSWindowDelegate {
    private let model = OverviewModel()
    private let tiler: Tiler
    private let settings = Settings.shared
    private var panel: OverviewPanel?
    private let frost = NSVisualEffectView()
    private var hosting: NSHostingView<OverviewView>?
    private var keyMonitor: Any?
    private var capture: Task<Void, Never>?
    private var escape: HotKey?
    private var generation = 0

    init(tiler: Tiler) {
        self.tiler = tiler
        super.init()
        model.onPick = { [weak self] slot in self?.pick(slot) }
        model.onDismiss = { [weak self] in self?.close() }
        model.onAllowPreviews = { [weak self] in
            Thumbnails.requestAccess()
            self?.close()
        }
    }

    var isOpen: Bool { keyMonitor != nil }

    func toggle() {
        isOpen ? close() : open()
    }

    func open() {
        guard !isOpen, let screen = Screen.underMouse else { return }
        tiler.pruneClosedWindows()
        let sets = settings.library.sets.sorted { $0.slot < $1.slot }
        model.reset(cards: sets.map { card(for: $0) })
        model.previewsAllowed = Thumbnails.isAllowed

        generation += 1
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.setFrame(screen.frame, display: false)
        // Esc must close the overview even when another app has taken keyboard focus, so it is
        // registered system-wide, and only while the overview is open.
        escape = HotKey(keyCode: kVK_Escape, modifiers: 0) { [weak self] in self?.close() }
        frost.alphaValue = 0
        fade([hosting].compactMap { $0 }, to: 1, duration: 0.01)
        panel.makeKeyAndOrderFront(nil)
        fade([frost], to: 1, duration: 0.16)
        withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.22)) { model.appeared = true }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
            return nil
        }
        refreshThumbnails(for: sets)
    }

    /// Always ends with the panel gone. Removal runs on a timer, never on an animation's
    /// completion, because a full-screen panel left behind would swallow every click.
    func close() {
        guard let keyMonitor else { return }
        NSEvent.removeMonitor(keyMonitor)
        self.keyMonitor = nil
        escape = nil
        capture?.cancel()
        generation += 1
        let generation = generation
        fade([frost, hosting].compactMap { $0 }, to: 0, duration: 0.18)
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard self.generation == generation else { return }
            panel?.orderOut(nil)
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    func pick(_ slot: Int) {
        guard isOpen, model.picked == nil else { return }
        // The set comes forward behind the overview, so the windows are in place when it clears.
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { model.picked = slot }
        close()
        tiler.recall(slot: slot, covered: true)
    }

    private func handle(_ event: NSEvent) {
        switch Int(event.keyCode) {
        case 0x35: close()
        case 0x24, 0x4C: model.pick()
        case 0x7B: model.move(by: -1)
        case 0x7C: model.move(by: 1)
        case 0x7E: model.move(by: -3)
        case 0x7D: model.move(by: 3)
        default:
            if let digit = event.charactersIgnoringModifiers?.first?.wholeNumberValue,
               let index = model.cards.firstIndex(where: { $0.slot == digit }) {
                model.select(index)
                model.pick()
            }
        }
    }

    private func card(for set: WindowSet) -> OverviewCard {
        let screen = NSScreen.screens.first { $0.persistentKey == set.displayKey } ?? NSScreen.main
        let size = screen?.visibleFrame.size ?? CGSize(width: 16, height: 10)
        let summary = SetSummary(set)
        return OverviewCard(slot: set.slot, grid: set.grid, title: summary.title,
                            windows: Dictionary(set.members.map { ($0.cell, $0.windowID) }, uniquingKeysWith: { first, _ in first }),
                            icons: summary.icons, aspect: size.width / max(size.height, 1), gap: settings.gap)
    }

    private func refreshThumbnails(for sets: [WindowSet]) {
        guard Thumbnails.isAllowed else { return }
        let ids = Set(sets.flatMap { $0.members.map(\.windowID) })
        capture?.cancel()
        capture = Task {
            let images = await Thumbnails.capture(ids, maxSide: 640)
            guard !Task.isCancelled else { return }
            for (id, image) in images {
                model.thumbnails[id] = NSImage(cgImage: image, size: .zero)
            }
        }
    }

    private func makePanel() -> OverviewPanel {
        let panel = OverviewPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.delegate = self

        let container = NSView()
        frost.material = .fullScreenUI
        frost.blendingMode = .behindWindow
        frost.state = .active
        frost.appearance = NSAppearance(named: .darkAqua)
        frost.autoresizingMask = [.width, .height]
        container.addSubview(frost)

        let hosting = NSHostingView(rootView: OverviewView(model: model))
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        self.hosting = hosting
        panel.contentView = container
        return panel
    }
}

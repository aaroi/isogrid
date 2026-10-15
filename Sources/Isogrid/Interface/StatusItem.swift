import AppKit
import IsogridCore
import ServiceManagement

/// The menu bar icon draws the current layout, so it doubles as a status indicator.
final class StatusItem: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let picker: PickerController
    private let overview: OverviewController
    private let tiler: Tiler
    private let settings = Settings.shared

    init(picker: PickerController, overview: OverviewController, tiler: Tiler) {
        self.picker = picker
        self.overview = overview
        self.tiler = tiler
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        refresh()
    }

    func refresh() {
        let layout = (NSScreen.main ?? NSScreen.screens.first).map(settings.layout(for:)) ?? .default
        item.button?.image = Self.icon(for: layout)
        item.button?.setAccessibilityLabel("Isogrid, \(layout.rows) by \(layout.columns)")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let screen = Screen.underMouse ?? NSScreen.main
        let current = screen.map(settings.layout(for:)) ?? .default

        let choose = NSMenuItem("Choose Layout…") { [weak self] in self?.picker.open() }
        choose.keyEquivalent = "g"
        choose.keyEquivalentModifierMask = [.option]
        menu.addItem(choose)
        let showSets = NSMenuItem("Show Sets…") { [weak self] in self?.overview.open() }
        showSets.keyEquivalent = " "
        showSets.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(showSets)
        menu.addItem(NSMenuItem("Tile Windows") { [weak self] in
            guard let self, let screen else { return }
            self.tiler.tile(on: screen)
        })
        menu.addItem(.separator())

        tiler.pruneClosedWindows()
        let sets = settings.library.sets.sorted { $0.slot < $1.slot }
        if !sets.isEmpty {
            menu.addItem(NSMenuItem.sectionHeader(title: "Sets"))
            for set in sets {
                let summary = SetSummary(set)
                let entry = NSMenuItem(summary.title) { [weak self] in self?.tiler.recall(slot: set.slot) }
                entry.keyEquivalent = "\(set.slot)"
                entry.keyEquivalentModifierMask = [.control, .option]
                entry.image = Self.icon(for: set.grid.layout)
                menu.addItem(entry)
            }
            menu.addItem(.separator())
        }

        let layouts = NSMenu()
        for layout in TileLayout.presets {
            let entry = NSMenuItem(layout.name) { [weak self] in
                guard let self, let screen else { return }
                self.tiler.apply(layout, on: screen)
                self.refresh()
            }
            entry.state = layout == current ? .on : .off
            entry.image = Self.icon(for: layout)
            layouts.addItem(entry)
        }
        menu.addItem(submenu("Layout", layouts))

        let modifiers = NSMenu()
        for modifier in DragModifier.allCases {
            let entry = NSMenuItem(modifier.title) { [weak self] in self?.settings.dragModifier = modifier }
            entry.state = modifier == settings.dragModifier ? .on : .off
            modifiers.addItem(entry)
        }
        menu.addItem(submenu("Hold While Dragging", modifiers))

        menu.addItem(.separator())
        menu.addItem(GapSlider(screen: screen, tiler: tiler).item)
        menu.addItem(.separator())

        if !AXWindow.isTrusted {
            menu.addItem(NSMenuItem("Allow Accessibility Access…") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
            })
        }
        let login = NSMenuItem("Open at Login") {
            let service = SMAppService.mainApp
            do {
                try service.status == .enabled ? service.unregister() : service.register()
            } catch {
                log.error("could not change Open at Login: \(error.localizedDescription, privacy: .public)")
            }
        }
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem("Quit Isogrid", key: "q") { NSApp.terminate(nil) })
    }

    private func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    static func icon(for layout: TileLayout) -> NSImage {
        let size = NSSize(width: 19, height: 14)
        let image = NSImage(size: size, flipped: true) { bounds in
            NSColor.black.set()
            let frame = bounds.insetBy(dx: 0.75, dy: 0.75)
            let outline = NSBezierPath(roundedRect: frame, xRadius: 3, yRadius: 3)
            outline.lineWidth = 1.5
            outline.stroke()
            for cell in layout.cellFrames(in: frame.insetBy(dx: 1, dy: 1), gap: 1.5) {
                NSBezierPath(roundedRect: cell, xRadius: 0.75, yRadius: 0.75).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// Menu items that run a closure. The item keeps its target alive through `representedObject`.
private final class MenuAction: NSObject {
    let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc func run() { handler() }
}

extension NSMenuItem {
    convenience init(_ title: String, key: String = "", handler: @escaping () -> Void) {
        let action = MenuAction(handler)
        self.init(title: title, action: #selector(MenuAction.run), keyEquivalent: key)
        target = action
        representedObject = action
    }
}

/// "Spacing" with a slider. Dragging previews the cells; letting go re-tiles.
private final class GapSlider: NSObject {
    let item = NSMenuItem()
    private let screen: NSScreen?
    private let tiler: Tiler
    private let value = NSTextField(labelWithString: "")
    private let settings = Settings.shared

    init(screen: NSScreen?, tiler: Tiler) {
        self.screen = screen
        self.tiler = tiler
        super.init()

        let title = NSTextField(labelWithString: "Spacing")
        title.font = .menuFont(ofSize: 0)
        value.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        value.textColor = .secondaryLabelColor
        value.alignment = .right
        let slider = NSSlider(value: Double(settings.gap), minValue: Double(Settings.gapRange.lowerBound),
                              maxValue: Double(Settings.gapRange.upperBound), target: self, action: #selector(changed(_:)))
        slider.controlSize = .small
        slider.isContinuous = true

        let row = NSStackView(views: [title, value])
        row.distribution = .fill
        let stack = NSStackView(views: [row, slider])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 14, bottom: 6, right: 14)
        stack.frame = CGRect(x: 0, y: 0, width: 220, height: 48)
        row.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -28).isActive = true
        slider.widthAnchor.constraint(equalTo: row.widthAnchor).isActive = true
        item.view = stack
        item.representedObject = self
        updateLabel()
    }

    @objc private func changed(_ slider: NSSlider) {
        settings.setGap(CGFloat(slider.doubleValue))
        updateLabel()
        guard let screen else { return }
        if NSApp.currentEvent?.type == .leftMouseUp {
            tiler.tile(on: screen)
        } else {
            tiler.preview(on: screen)
        }
    }

    private func updateLabel() {
        value.stringValue = "\(Int(settings.gap)) pt"
    }
}

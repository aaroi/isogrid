#if DEBUG
import AppKit
import IsogridCore
import SwiftUI

/// `Isogrid --snapshot <dir>` renders the picker in both appearances, the overview and the
/// menu bar icons to PNGs, for reviewing the design without Screen Recording permission.
enum Snapshot {
    static func run(into directory: URL) {
        PanelSurface.isSnapshot = true
        let model = PickerModel()
        var library = SetLibrary()
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.map(\.processIdentifier)
        let pid = { (i: Int) in apps.isEmpty ? ProcessInfo.processInfo.processIdentifier : apps[i % min(apps.count, 3)] }
        library.record(grid: TileGrid(TileLayout(rows: 2, columns: 4)!),
                       members: (0..<8).map { .init(windowID: UInt32($0 + 1), pid: pid($0 < 5 ? 0 : 1), cell: $0) }, on: "A", at: .now)
        library.record(grid: TileGrid(TileLayout(rows: 1, columns: 3)!),
                       members: (0..<3).map { .init(windowID: UInt32($0 + 20), pid: pid($0), cell: $0) }, on: "A", at: .now)
        model.reset(current: TileLayout(rows: 2, columns: 4)!, sets: library.sets.map(SetSummary.init))
        model.moveRow(by: 1)
        let typing = PickerModel()
        typing.reset(current: .default, sets: [])
        typing.type(2)

        for (name, model) in [("picker", model), ("picker-typing", typing)] {
            for scheme in [ColorScheme.light, .dark] {
                let view = PickerView(model: model)
                    .environment(\.colorScheme, scheme)
                    .background(scheme == .dark ? Color(white: 0.16) : Color(white: 0.86))
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                write(renderer.cgImage, to: directory.appending(path: "\(name)-\(scheme == .dark ? "dark" : "light").png"))
            }
        }

        let overview = OverviewModel()
        overview.reset(cards: library.sets.sorted { $0.slot < $1.slot }.map { set in
            let summary = SetSummary(set)
            return OverviewCard(slot: set.slot, grid: set.grid, title: summary.title,
                                windows: Dictionary(set.members.map { ($0.cell, $0.windowID) }, uniquingKeysWith: { a, _ in a }),
                                icons: summary.icons, aspect: 1512.0 / 920, gap: 8)
        })
        overview.appeared = true
        let overviewView = OverviewView(model: overview)
            .frame(width: 1512, height: 982)
            .background(LinearGradient(colors: [Color(red: 0.12, green: 0.16, blue: 0.35), Color(red: 0.05, green: 0.06, blue: 0.12)],
                                       startPoint: .top, endPoint: .bottom))
        let overviewRenderer = ImageRenderer(content: overviewView)
        overviewRenderer.scale = 1
        write(overviewRenderer.cgImage, to: directory.appending(path: "overview.png"))

        for layout in TileLayout.presets {
            let icon = StatusItem.icon(for: layout)
            var rect = CGRect(origin: .zero, size: icon.size)
            write(icon.cgImage(forProposedRect: &rect, context: nil, hints: [.ctm: AffineTransform(scale: 4)]),
                  to: directory.appending(path: "icon-\(layout.id).png"))
        }
    }

    private static func write(_ image: CGImage?, to url: URL) {
        guard let image else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif

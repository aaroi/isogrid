import AppKit
import IsogridCore

/// A set as the picker, overview and menu show it, named after the apps in it.
struct SetSummary: Identifiable {
    let slot: Int
    let grid: TileGrid
    let icons: [Int: NSImage]
    let title: String
    var id: Int { slot }

    init(_ set: WindowSet) {
        slot = set.slot
        grid = set.grid
        let apps = set.members.map { (cell: $0.cell, app: NSRunningApplication(processIdentifier: $0.pid)) }
        icons = Dictionary(apps.compactMap { item in item.app?.icon.map { (item.cell, $0) } }, uniquingKeysWith: { first, _ in first })
        let counts = Dictionary(grouping: apps.compactMap { $0.app?.localizedName }, by: { $0 }).mapValues(\.count)
        title = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { $0.value > 1 ? "\($0.key) ×\($0.value)" : $0.key }
            .joined(separator: ", ")
    }
}

import AppKit
import IsogridCore

enum DragModifier: String, CaseIterable {
    case shift, control, option, command

    var flags: NSEvent.ModifierFlags {
        switch self {
        case .shift: .shift
        case .control: .control
        case .option: .option
        case .command: .command
        }
    }

    var title: String {
        switch self {
        case .shift: "⇧ Shift"
        case .control: "⌃ Control"
        case .option: "⌥ Option"
        case .command: "⌘ Command"
        }
    }
}

@Observable
final class Settings {
    static let shared = Settings()
    static let gapRange: ClosedRange<CGFloat> = 0...32

    /// The end-to-end test instance keeps its settings and sets apart from yours.
    nonisolated(unsafe) static var suiteName: String?

    private let defaults = Settings.suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard

    var dragModifier: DragModifier {
        didSet { defaults.set(dragModifier.rawValue, forKey: "dragModifier") }
    }

    /// Set through `setGap(_:)`, which rounds and clamps. Clamping in `didSet` would recurse,
    /// because the Observation macro routes that assignment back through this setter.
    private(set) var gap: CGFloat {
        didSet { defaults.set(Double(gap), forKey: "gap") }
    }

    func setGap(_ value: CGFloat) {
        let clamped = min(max(value.rounded(), Self.gapRange.lowerBound), Self.gapRange.upperBound)
        if clamped != gap { gap = clamped }
    }

    /// Grid per display, keyed by `NSScreen.persistentKey`.
    private(set) var grids: [String: TileGrid] {
        didSet {
            if let data = try? JSONEncoder().encode(grids) { defaults.set(data, forKey: "grids") }
        }
    }

    /// Window sets, saved so slots survive a restart. Windows that closed meanwhile are pruned.
    var library: SetLibrary {
        didSet {
            if let data = try? JSONEncoder().encode(library) { defaults.set(data, forKey: "sets") }
            if Set(library.sets.flatMap { $0.members.map(\.pid) }) != Set(oldValue.sets.flatMap { $0.members.map(\.pid) }) {
                onLibraryAppsChange()
            }
        }
    }

    /// Called when the set of apps with windows in a set changes.
    @ObservationIgnored var onLibraryAppsChange: () -> Void = {}

    private init() {
        // Option-drag is taken by macOS tiling, and Control-click becomes a right-click,
        // so Shift is the default that collides with the least.
        dragModifier = defaults.string(forKey: "dragModifier").flatMap(DragModifier.init) ?? .shift
        gap = defaults.object(forKey: "gap").map { CGFloat(($0 as? Double) ?? 8) } ?? 8
        var library = defaults.data(forKey: "sets").flatMap { try? JSONDecoder().decode(SetLibrary.self, from: $0) } ?? SetLibrary()
        library.makeExclusive()
        self.library = library
        displays = defaults.data(forKey: "displays").flatMap { try? JSONDecoder().decode([String: DisplayInfo].self, from: $0) } ?? [:]
        grids = defaults.data(forKey: "grids").flatMap { try? JSONDecoder().decode([String: TileGrid].self, from: $0) } ?? [:]
    }

    /// Name and size of each display a grid was saved for, to recognise it if its ID changes.
    struct DisplayInfo: Codable, Equatable {
        let name: String
        let width: Double
        let height: Double

        init(_ screen: NSScreen) {
            name = screen.localizedName
            width = screen.frame.width
            height = screen.frame.height
        }
    }

    private(set) var displays: [String: DisplayInfo] {
        didSet {
            if let data = try? JSONEncoder().encode(displays) { defaults.set(data, forKey: "displays") }
        }
    }

    /// macOS can give a monitor a new ID when it reconnects through another port, dock or hub.
    /// Grids and sets saved under an ID that's no longer connected move to the connected display
    /// with the same name and size, or, for data saved before sizes were recorded, to the
    /// display that holds most of the set's windows.
    func reconcileDisplays() {
        let screens = NSScreen.screens
        let connected = Set(screens.map(\.persistentKey))
        for screen in screens where grids[screen.persistentKey] != nil {
            if displays[screen.persistentKey] == nil { displays[screen.persistentKey] = DisplayInfo(screen) }
        }
        let stored = Set(grids.keys).union(library.sets.map(\.displayKey))
        let windows = WindowList.onScreen()

        for orphan in stored.subtracting(connected).sorted() {
            let free = screens.filter { screen in
                grids[screen.persistentKey] == nil && !library.sets.contains { $0.displayKey == screen.persistentKey }
            }
            let match: NSScreen?
            if let info = displays[orphan] {
                match = free.first { DisplayInfo($0) == info }
            } else {
                let members = Set(library.sets.filter { $0.displayKey == orphan }.flatMap { $0.members.map(\.windowID) })
                let centers = windows.filter { members.contains($0.id) }.map(\.bounds.center)
                match = free.map { screen in (screen, centers.filter { screen.axFrame.contains($0) }.count) }
                    .filter { $0.1 > 0 }
                    .max { $0.1 < $1.1 }?.0
            }
            guard let match else { continue }
            let key = match.persistentKey
            log.info("display \(orphan, privacy: .public) is now \(key, privacy: .public) (\(match.localizedName, privacy: .public))")
            if let grid = grids.removeValue(forKey: orphan) { grids[key] = grid }
            displays.removeValue(forKey: orphan)
            displays[key] = DisplayInfo(match)
            library.moveDisplay(from: orphan, to: key)
        }
    }

    func grid(for screen: NSScreen) -> TileGrid {
        grids[screen.persistentKey] ?? TileGrid(.default)
    }

    func layout(for screen: NSScreen) -> TileLayout {
        grid(for: screen).layout
    }

    func setGrid(_ grid: TileGrid, for screen: NSScreen) {
        grids[screen.persistentKey] = grid
        if displays[screen.persistentKey] != DisplayInfo(screen) { displays[screen.persistentKey] = DisplayInfo(screen) }
    }
}

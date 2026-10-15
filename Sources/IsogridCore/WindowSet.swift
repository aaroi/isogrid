import CoreGraphics
import Foundation

/// A group of windows tiled together on one display, recalled by its slot number.
public struct WindowSet: Codable, Hashable, Sendable, Identifiable {
    public struct Member: Codable, Hashable, Sendable {
        public let windowID: UInt32
        public let pid: Int32
        public var cell: Int

        public init(windowID: UInt32, pid: Int32, cell: Int) {
            self.windowID = windowID
            self.pid = pid
            self.cell = cell
        }
    }

    public let id: UUID
    public let slot: Int
    public internal(set) var displayKey: String
    public var grid: TileGrid
    public var members: [Member]
    public var lastUsed: Date
}

/// The saved sets. Sets form on their own whenever windows are tiled, and tiling mostly the
/// same windows again updates their set.
public struct SetLibrary: Codable, Hashable, Sendable {
    public static let slots = 1...9

    public internal(set) var sets: [WindowSet] = []

    public init() {}

    public func set(inSlot slot: Int) -> WindowSet? {
        sets.first { $0.slot == slot }
    }

    /// The set most recently tiled or recalled on a display; drags and gap changes update it.
    public func active(on displayKey: String) -> WindowSet? {
        sets.filter { $0.displayKey == displayKey }.max { $0.lastUsed < $1.lastUsed }
    }

    /// Records a tiling and returns the set that now holds it.
    @discardableResult
    public mutating func record(grid: TileGrid, members: [WindowSet.Member], on displayKey: String, at now: Date) -> WindowSet? {
        guard !members.isEmpty else { return nil }
        let ids = Set(members.map(\.windowID))

        // Sharing at least half of the larger group, on the same display, makes it the same set.
        let match = sets.indices
            .filter { sets[$0].displayKey == displayKey }
            .map { index in (index, ids.intersection(sets[index].members.map(\.windowID)).count) }
            .filter { index, shared in shared * 2 >= max(ids.count, sets[index].members.count) }
            .max { $0.1 < $1.1 }
        // A window belongs to one set only; joining this one takes it out of any other.
        let keep = match.map { sets[$0.0].id }
        for index in sets.indices where sets[index].id != keep {
            sets[index].members.removeAll { ids.contains($0.windowID) }
        }
        sets.removeAll { $0.members.isEmpty && $0.id != keep }

        if let id = keep, let index = sets.firstIndex(where: { $0.id == id }) {
            sets[index].grid = grid
            sets[index].members = members
            sets[index].lastUsed = now
            return sets[index]
        }

        let used = Set(sets.map(\.slot))
        let slot: Int
        if let free = Self.slots.first(where: { !used.contains($0) }) {
            slot = free
        } else if let oldest = sets.min(by: { $0.lastUsed < $1.lastUsed }) {
            slot = oldest.slot
            sets.removeAll { $0.id == oldest.id }
        } else {
            return nil
        }
        let set = WindowSet(id: UUID(), slot: slot, displayKey: displayKey, grid: grid, members: members, lastUsed: now)
        sets.append(set)
        return set
    }

    public mutating func touch(_ id: UUID, at now: Date) {
        guard let index = sets.firstIndex(where: { $0.id == id }) else { return }
        sets[index].lastUsed = now
    }

    /// A window dropped into a cell joins the display's active set, taking over that cell.
    public mutating func place(windowID: UInt32, pid: Int32, inCell cell: Int, on displayKey: String) {
        guard let active = active(on: displayKey) else { return }
        for index in sets.indices where sets[index].id != active.id {
            sets[index].members.removeAll { $0.windowID == windowID }
        }
        sets.removeAll { $0.members.isEmpty && $0.id != active.id }
        guard let index = sets.firstIndex(where: { $0.id == active.id }) else { return }
        sets[index].members.removeAll { $0.windowID == windowID || $0.cell == cell }
        sets[index].members.append(.init(windowID: windowID, pid: pid, cell: cell))
    }

    /// Moves sets to a display's new ID, after it reconnects through another port or dock.
    public mutating func moveDisplay(from old: String, to new: String) {
        for index in sets.indices where sets[index].displayKey == old {
            sets[index].displayKey = new
        }
    }

    public mutating func updateGrid(_ grid: TileGrid, ofSet id: UUID) {
        guard let index = sets.firstIndex(where: { $0.id == id }), sets[index].grid.layout == grid.layout else { return }
        sets[index].grid = grid
    }

    /// Gives each window to its most recently used set, for libraries saved before a window
    /// could only belong to one.
    public mutating func makeExclusive() {
        var claimed = Set<UInt32>()
        for set in sets.sorted(by: { $0.lastUsed > $1.lastUsed }) {
            guard let index = sets.firstIndex(where: { $0.id == set.id }) else { continue }
            sets[index].members.removeAll { !claimed.insert($0.windowID).inserted }
        }
        sets.removeAll { $0.members.isEmpty }
    }

    public mutating func remove(windowIDs: Set<UInt32>) {
        prune(keeping: Set(sets.flatMap { $0.members.map(\.windowID) }).subtracting(windowIDs))
    }

    /// Drops windows that have closed, and sets left with none.
    public mutating func prune(keeping alive: Set<UInt32>) {
        for index in sets.indices {
            sets[index].members.removeAll { !alive.contains($0.windowID) }
        }
        sets.removeAll { $0.members.isEmpty }
    }
}

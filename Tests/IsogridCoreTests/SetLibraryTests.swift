import Foundation
import Testing
@testable import IsogridCore

struct SetLibraryTests {
    let grid = TileGrid(TileLayout(rows: 1, columns: 2)!)
    let t0 = Date(timeIntervalSince1970: 0)

    func members(_ ids: [UInt32]) -> [WindowSet.Member] {
        ids.enumerated().map { .init(windowID: $1, pid: 1, cell: $0) }
    }

    @Test func tilingFillsSlotsInOrder() {
        var library = SetLibrary()
        library.record(grid: grid, members: members([1, 2]), on: "A", at: t0)
        library.record(grid: grid, members: members([3, 4]), on: "A", at: t0 + 1)
        #expect(library.set(inSlot: 1)?.members.map(\.windowID) == [1, 2])
        #expect(library.set(inSlot: 2)?.members.map(\.windowID) == [3, 4])
    }

    @Test func retilingMostlyTheSameWindowsUpdatesTheSet() {
        var library = SetLibrary()
        library.record(grid: grid, members: members([1, 2, 3, 4]), on: "A", at: t0)
        library.record(grid: grid, members: members([1, 2, 3, 5]), on: "A", at: t0 + 1)
        #expect(library.sets.count == 1)
        #expect(library.set(inSlot: 1)?.members.map(\.windowID) == [1, 2, 3, 5])
    }

    @Test func windowsTiledOnAnotherDisplayMoveToANewSet() {
        var library = SetLibrary()
        library.record(grid: grid, members: members([1, 2]), on: "A", at: t0)
        library.record(grid: grid, members: members([1, 2]), on: "B", at: t0 + 1)
        #expect(library.sets.count == 1)
        #expect(library.sets.first?.displayKey == "B")
    }

    @Test func fullLibraryReplacesTheLeastRecentlyUsed() {
        var library = SetLibrary()
        for i in 0..<9 {
            library.record(grid: grid, members: members([UInt32(i * 10)]), on: "A", at: t0 + Double(i))
        }
        library.touch(library.set(inSlot: 1)!.id, at: t0 + 100)
        library.record(grid: grid, members: members([999]), on: "A", at: t0 + 101)
        #expect(library.sets.count == 9)
        #expect(library.set(inSlot: 2)?.members.map(\.windowID) == [999])
        #expect(library.set(inSlot: 1)?.members.map(\.windowID) == [0])
    }

    @Test func droppedWindowTakesOverACellInTheActiveSet() {
        var library = SetLibrary()
        library.record(grid: grid, members: members([1, 2]), on: "A", at: t0)
        library.place(windowID: 7, pid: 3, inCell: 1, on: "A")
        #expect(library.set(inSlot: 1)?.members.map(\.windowID).sorted() == [1, 7])
    }

    @Test func closedWindowsAndEmptySetsArePruned() {
        var library = SetLibrary()
        library.record(grid: grid, members: members([1, 2]), on: "A", at: t0)
        library.record(grid: grid, members: members([3]), on: "A", at: t0 + 1)
        library.prune(keeping: [1])
        #expect(library.sets.count == 1)
        #expect(library.set(inSlot: 1)?.members.map(\.windowID) == [1])
    }

    @Test func aWindowBelongsToOneSetOnly() {
        var library = SetLibrary()
        library.record(grid: grid, members: members([1, 2, 3]), on: "A", at: t0)
        library.record(grid: grid, members: members([3, 4, 5]), on: "A", at: t0 + 1)
        #expect(library.set(inSlot: 1)?.members.map(\.windowID) == [1, 2])
        #expect(library.set(inSlot: 2)?.members.map(\.windowID) == [3, 4, 5])
    }

    @Test func takingEveryWindowEmptiesTheOldSet() {
        var library = SetLibrary()
        library.record(grid: grid, members: members([1, 2]), on: "A", at: t0)
        library.record(grid: grid, members: members([1, 2, 3, 4, 5]), on: "A", at: t0 + 1)
        #expect(library.sets.count == 1)
        #expect(library.sets.first?.members.count == 5)
    }

    @Test func makeExclusiveKeepsSharedWindowsInTheNewestSet() {
        var library = SetLibrary()
        library.record(grid: grid, members: members([1, 2]), on: "A", at: t0)
        library.record(grid: grid, members: members([3, 4]), on: "A", at: t0 + 1)
        // A library saved before membership was exclusive: window 3 also sits in the older set.
        library.sets[0].members.append(.init(windowID: 3, pid: 1, cell: 2))
        library.makeExclusive()
        #expect(library.set(inSlot: 1)?.members.map(\.windowID) == [1, 2])
        #expect(library.set(inSlot: 2)?.members.map(\.windowID) == [3, 4])
    }

    @Test func setsFollowADisplayToItsNewID() {
        var library = SetLibrary()
        library.record(grid: grid, members: members([1, 2]), on: "old", at: t0)
        library.record(grid: grid, members: members([3]), on: "other", at: t0 + 1)
        library.moveDisplay(from: "old", to: "new")
        #expect(library.set(inSlot: 1)?.displayKey == "new")
        #expect(library.set(inSlot: 2)?.displayKey == "other")
        #expect(library.active(on: "new")?.slot == 1)
    }
}

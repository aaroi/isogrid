import CoreGraphics
import Foundation
import Testing
@testable import IsogridCore

struct TileLayoutTests {
    @Test(arguments: [("2x4", 2, 4), ("2×4", 2, 4), ("24", 2, 4), ("1 x 3", 1, 3)])
    func parses(_ input: String, rows: Int, columns: Int) {
        #expect(TileLayout(input) == TileLayout(rows: rows, columns: columns))
    }

    @Test(arguments: ["0x2", "2x9", "7x1", "abc", "", "123"])
    func rejects(_ input: String) {
        #expect(TileLayout(input) == nil)
    }

    @Test func cellsTileTheAreaWithEvenGaps() throws {
        let layout = try #require(TileLayout(rows: 2, columns: 3))
        let area = CGRect(x: 0, y: 25, width: 1512, height: 920)
        let cells = layout.cellFrames(in: area, gap: 8)

        #expect(cells.count == 6)
        #expect(cells[0].minX == 8)
        #expect(cells[0].minY == 33)
        #expect(cells[2].maxX == area.maxX - 8)
        #expect(cells[5].maxY == area.maxY - 8)
        for cell in cells {
            #expect(cell.origin.x == cell.origin.x.rounded())
            #expect(cell.maxX == cell.maxX.rounded())
        }
        // Neighbours are exactly one gap apart.
        #expect(cells[1].minX - cells[0].maxX == 8)
        #expect(cells[3].minY - cells[0].maxY == 8)
    }

    @Test func zeroGapCellsShareEdges() throws {
        let layout = try #require(TileLayout(rows: 1, columns: 3))
        let cells = layout.cellFrames(in: CGRect(x: 0, y: 0, width: 1000, height: 600), gap: 0)
        #expect(cells[0].maxX == cells[1].minX)
        #expect(cells[1].maxX == cells[2].minX)
        #expect(cells[2].maxX == 1000)
    }

    @Test func nearestCellCoversGaps() {
        let cells = [CGRect(x: 0, y: 0, width: 100, height: 100), CGRect(x: 110, y: 0, width: 100, height: 100)]
        #expect(GridMath.cell(nearest: CGPoint(x: 50, y: 50), in: cells) == 0)
        #expect(GridMath.cell(nearest: CGPoint(x: 107, y: 50), in: cells) == 1)
        #expect(GridMath.cell(nearest: CGPoint(x: 500, y: -40), in: cells) == 1)
    }

    @Test func reapplyingKeepsWindowsInPlace() throws {
        let cells = try #require(TileLayout(rows: 2, columns: 2)).cellFrames(in: CGRect(x: 0, y: 0, width: 800, height: 600), gap: 0)
        // Front-most window sits in the bottom-right cell; it should stay there.
        let windows = [cells[3], cells[0], cells[2], cells[1]]
        #expect(GridMath.assign(windows: windows, to: cells) == [3, 0, 2, 1])
    }

    @Test func pileFillsInReadingOrderAndOverflowStays() throws {
        let cells = try #require(TileLayout(rows: 1, columns: 2)).cellFrames(in: CGRect(x: 0, y: 0, width: 800, height: 600), gap: 0)
        let pile = Array(repeating: CGRect(x: 300, y: 100, width: 200, height: 200), count: 3)
        #expect(GridMath.assign(windows: pile, to: cells) == [0, 1, nil])
    }
}

struct SwapTests {
    let cells = TileLayout(rows: 1, columns: 4)!.cellFrames(in: CGRect(x: 0, y: 0, width: 1600, height: 900), gap: 8)

    @Test func droppingOnAnOccupiedCellSwaps() {
        #expect(GridMath.swapDestination(from: 0, into: 2, occupied: [1, 2, 3], cells: cells) == 0)
    }

    @Test func droppingOnAFreeCellMovesNothingElse() {
        #expect(GridMath.swapDestination(from: 0, into: 2, occupied: [1, 3], cells: cells) == nil)
    }

    @Test func aWindowFromOutsidePushesTheOccupantToTheNearestEmptyCell() {
        #expect(GridMath.swapDestination(from: nil, into: 1, occupied: [0, 1], cells: cells) == 2)
        #expect(GridMath.swapDestination(from: nil, into: 1, occupied: [0, 1, 2, 3], cells: cells) == nil)
    }

    @Test func droppingBackInItsOwnCellMovesNothingElse() {
        #expect(GridMath.swapDestination(from: 2, into: 2, occupied: [0, 1, 3], cells: cells) == nil)
    }
}

struct TileGridTests {
    let area = CGRect(x: 0, y: 0, width: 1600, height: 1000)

    func midGap(_ cells: [CGRect], _ left: Int, _ right: Int) -> CGFloat { (cells[left].maxX + cells[right].minX) / 2 }

    @Test func findsDividersInGaps() throws {
        let grid = TileGrid(try #require(TileLayout(rows: 2, columns: 2)))
        let cells = grid.cellFrames(in: area, gap: 8)
        let x = midGap(cells, 0, 1)

        let pair = grid.divider(at: CGPoint(x: x, y: 300), in: area, gap: 8, scope: .pair)
        #expect(pair == .init(axis: .vertical, before: [0], after: [1]))
        let line = grid.divider(at: CGPoint(x: x, y: 300), in: area, gap: 8, scope: .line)
        #expect(line == .init(axis: .vertical, before: [0, 2], after: [1, 3]))
        let row = grid.divider(at: CGPoint(x: 300, y: (cells[0].maxY + cells[2].minY) / 2), in: area, gap: 8, scope: .line)
        #expect(row == .init(axis: .horizontal, before: [0, 1], after: [2, 3]))
        #expect(grid.divider(at: CGPoint(x: 300, y: 300), in: area, gap: 8, scope: .line) == nil)
        #expect(grid.divider(at: CGPoint(x: 2, y: 300), in: area, gap: 8, scope: .line) == nil)
    }

    @Test func uniformCellsMatchTheLayout() throws {
        let layout = try #require(TileLayout(rows: 2, columns: 3))
        #expect(TileGrid(layout).cellFrames(in: area, gap: 8) == layout.cellFrames(in: area, gap: 8))
    }

    @Test func movingALineResizesItsNeighboursInEveryRow() throws {
        var grid = TileGrid(try #require(TileLayout(rows: 2, columns: 3)))
        let before = grid.cellFrames(in: area, gap: 8)
        let divider = try #require(grid.divider(at: CGPoint(x: midGap(before, 0, 1), y: 300), in: area, gap: 8, scope: .line))
        grid.move(divider, to: 700, in: area, gap: 8)
        let after = grid.cellFrames(in: area, gap: 8)

        for row in [0, 3] {
            #expect(after[row].minX == before[row].minX)
            #expect(abs(after[row].maxX - 696) <= 1)
            #expect(abs(after[row + 1].minX - 704) <= 1)
            #expect(after[row + 1].maxX == before[row + 1].maxX)
            #expect(after[row + 2] == before[row + 2])
        }
    }

    @Test func movingAPairLeavesTheRestOfTheColumn() throws {
        var grid = TileGrid(try #require(TileLayout(rows: 2, columns: 2)))
        let before = grid.cellFrames(in: area, gap: 8)
        let divider = try #require(grid.divider(at: CGPoint(x: midGap(before, 0, 1), y: 300), in: area, gap: 8, scope: .pair))
        grid.move(divider, to: 600, in: area, gap: 8)
        let after = grid.cellFrames(in: area, gap: 8)

        #expect(abs(after[0].maxX - 596) <= 1)
        #expect(abs(after[1].minX - 604) <= 1)
        #expect(after[2] == before[2])
        #expect(after[3] == before[3])
        // The bottom row's gap is still where it was, and is now its own line.
        let bottom = grid.divider(at: CGPoint(x: midGap(after, 2, 3), y: 800), in: area, gap: 8, scope: .line)
        #expect(bottom == .init(axis: .vertical, before: [2], after: [3]))
    }

    @Test func aPairSnapsToTheEdgeInTheRowAbove() throws {
        // 2×4: move the top row's 3|4 gap, then drag the bottom row's 7|8 gap close to it.
        var grid = TileGrid(try #require(TileLayout(rows: 2, columns: 4)))
        grid.move(.init(axis: .vertical, before: [2], after: [3]), to: 1300, in: area, gap: 8)
        let top = grid.cellFrames(in: area, gap: 8)[2].maxX
        let snapped = grid.move(.init(axis: .vertical, before: [6], after: [7]), to: top + 4 + 9, in: area, gap: 8, snap: 12)
        let cells = grid.cellFrames(in: area, gap: 8)
        #expect(snapped)
        #expect(cells[6].maxX == cells[2].maxX)
        #expect(cells[7].minX == cells[3].minX)
    }

    @Test func aGapSnapsBackToAnEvenSplit() throws {
        var grid = TileGrid(try #require(TileLayout(rows: 1, columns: 2)))
        let divider = TileGrid.Divider(axis: .vertical, before: [0], after: [1])
        grid.move(divider, to: 1000, in: area, gap: 8)
        grid.move(divider, to: 806, in: area, gap: 8, snap: 12)
        #expect(grid == TileGrid(try #require(TileLayout(rows: 1, columns: 2))))
    }

    @Test func farFromAnyEdgeNothingSnaps() throws {
        var grid = TileGrid(try #require(TileLayout(rows: 1, columns: 2)))
        let snapped = grid.move(.init(axis: .vertical, before: [0], after: [1]), to: 1000, in: area, gap: 8, snap: 12)
        #expect(!snapped)
    }

    @Test func dividersStopAtTheMinimum() throws {
        var grid = TileGrid(try #require(TileLayout(rows: 1, columns: 2)))
        let divider = TileGrid.Divider(axis: .vertical, before: [0], after: [1])
        grid.move(divider, to: 10, in: area, gap: 8, minimum: 200)
        #expect(abs(grid.cellFrames(in: area, gap: 8)[0].width - 200) <= 1)
    }

    @Test func roundTripsThroughCodable() throws {
        var grid = TileGrid(try #require(TileLayout(rows: 2, columns: 3)))
        grid.move(.init(axis: .horizontal, before: [0], after: [3]), to: 300, in: area, gap: 8)
        let decoded = try JSONDecoder().decode(TileGrid.self, from: JSONEncoder().encode(grid))
        #expect(decoded == grid)
    }

    @Test func cellsThatDontFitTheLayoutDecodeAsEqualCells() throws {
        let json = #"{"layout":{"rows":1,"columns":2},"cells":[{"minX":0,"minY":0,"maxX":1,"maxY":1}]}"#
        let grid = try JSONDecoder().decode(TileGrid.self, from: Data(json.utf8))
        #expect(grid == TileGrid(try #require(TileLayout(rows: 1, columns: 2))))
    }

    @Test func matchesWindowsToCellsWithTolerance() {
        let cells = [CGRect(x: 0, y: 0, width: 400, height: 400), CGRect(x: 408, y: 0, width: 400, height: 400)]
        let windows = [CGRect(x: 2, y: 0, width: 396, height: 410), CGRect(x: 100, y: 100, width: 200, height: 200)]
        #expect(GridMath.match(windows: windows, to: cells) == [0, nil])
    }
}

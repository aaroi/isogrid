import CoreGraphics

/// A grid of `rows` × `columns` equal cells. "2x4" means two rows of four.
public struct TileLayout: Hashable, Sendable, Codable {
    public static let maxRows = 6
    public static let maxColumns = 8

    public let rows: Int
    public let columns: Int

    public init?(rows: Int, columns: Int) {
        guard (1...Self.maxRows).contains(rows), (1...Self.maxColumns).contains(columns) else { return nil }
        self.init(validRows: rows, columns: columns)
    }

    private init(validRows rows: Int, columns: Int) {
        self.rows = rows
        self.columns = columns
    }

    /// Parses "2x4", "2×4" or "24".
    public init?(_ string: String) {
        let digits = string.lowercased().split { "x× *".contains($0) }
        if digits.count == 2, let rows = Int(digits[0]), let columns = Int(digits[1]) {
            self.init(rows: rows, columns: columns)
        } else if string.count == 2, let rows = string.first?.wholeNumberValue, let columns = string.last?.wholeNumberValue {
            self.init(rows: rows, columns: columns)
        } else {
            return nil
        }
    }

    public static let presets: [TileLayout] = [(1, 2), (1, 3), (1, 4), (2, 2), (2, 3), (2, 4), (3, 3), (3, 4)]
        .map { TileLayout(validRows: $0.0, columns: $0.1) }

    public static let `default` = TileLayout(validRows: 1, columns: 2)

    public var cellCount: Int { rows * columns }
    public var name: String { "\(rows)×\(columns)" }
    public var id: String { "\(rows)x\(columns)" }

    /// Equal cells in row-major order, in a top-left-origin space. Edges are rounded to whole
    /// points so neighbours never overlap or leave hairline seams.
    public func cellFrames(in area: CGRect, gap: CGFloat) -> [CGRect] {
        TileGrid(self).cellFrames(in: area, gap: gap)
    }
}

public enum GridMath {
    /// The cell under `point`, or the closest one when the point sits in a gap or off the grid.
    public static func cell(nearest point: CGPoint, in cells: [CGRect]) -> Int? {
        cells.indices.min { distance(from: point, to: cells[$0]) < distance(from: point, to: cells[$1]) }
    }

    /// Assigns windows (front-most first) to cells. Each window takes the free cell nearest its
    /// centre, so re-applying a layout leaves windows where they are, and a pile of overlapping
    /// windows fills the grid in reading order. Windows beyond the cell count get `nil`.
    public static func assign(windows: [CGRect], to cells: [CGRect]) -> [Int?] {
        var free = Array(cells.indices)
        return windows.map { window in
            let center = CGPoint(x: window.midX, y: window.midY)
            guard let best = free.min(by: { distance(from: center, to: cells[$0]) < distance(from: center, to: cells[$1]) }) else {
                return nil
            }
            free.removeAll { $0 == best }
            return best
        }
    }

    /// Where the window already in `target` goes when another window is dropped on it. It takes
    /// the dropped window's old cell, so the two swap. When the dropped window came from outside
    /// the grid, it takes the empty cell nearest the target. `nil` when the target is free or no
    /// cell is.
    public static func swapDestination(from origin: Int?, into target: Int, occupied: Set<Int>, cells: [CGRect]) -> Int? {
        guard occupied.contains(target) else { return nil }
        if let origin, origin != target { return origin }
        let center = CGPoint(x: cells[target].midX, y: cells[target].midY)
        return cells.indices
            .filter { $0 != target && !occupied.contains($0) }
            .min { distance(from: center, to: cells[$0]) < distance(from: center, to: cells[$1]) }
    }

    static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}

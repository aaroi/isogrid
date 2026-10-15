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

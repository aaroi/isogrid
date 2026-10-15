import CoreGraphics

/// A layout whose cells can be resized by dragging the gaps between them. Each cell keeps its
/// own edges, in 0–1 coordinates of the screen area, so one pair of windows can be resized
/// without the rest of its row or column.
public struct TileGrid: Hashable, Sendable {
    /// Cell edges as fractions of the area.
    public struct Edges: Hashable, Sendable, Codable {
        public var minX, minY, maxX, maxY: Double
    }

    /// A gap between cells. `before` are the cells to its left (or above), `after` to its right (or below).
    public struct Divider: Hashable, Sendable {
        public enum Axis: Hashable, Sendable {
            /// A vertical gap, dragged left and right.
            case vertical
            /// A horizontal gap, dragged up and down.
            case horizontal
        }

        public let axis: Axis
        public let before: [Int]
        public let after: [Int]
    }

    /// How much a gap drag resizes.
    public enum Scope: Sendable {
        /// Only the two cells on either side of the pointer.
        case pair
        /// Every cell whose edge lines up with that gap, across the whole grid.
        case line
    }

    public let layout: TileLayout
    public private(set) var cells: [Edges]

    private static let epsilon = 0.0005

    public init(_ layout: TileLayout) {
        self.layout = layout
        let columns = Double(layout.columns), rows = Double(layout.rows)
        cells = (0..<layout.cellCount).map { index in
            let row = Double(index / layout.columns), column = Double(index % layout.columns)
            return Edges(minX: column / columns, minY: row / rows, maxX: (column + 1) / columns, maxY: (row + 1) / rows)
        }
    }

    /// Cell frames in a top-left-origin space, with `gap` points between cells and around the
    /// edge. Edges land on whole points so neighbours never overlap or leave hairline seams.
    public func cellFrames(in area: CGRect, gap: CGFloat) -> [CGRect] {
        cells.map { edges in
            let minX = (Self.point(edges.minX, area.minX, area.width, gap) + gap / 2).rounded()
            let maxX = (Self.point(edges.maxX, area.minX, area.width, gap) - gap / 2).rounded()
            let minY = (Self.point(edges.minY, area.minY, area.height, gap) + gap / 2).rounded()
            let maxY = (Self.point(edges.maxY, area.minY, area.height, gap) - gap / 2).rounded()
            return CGRect(x: minX, y: minY, width: max(maxX - minX, 0), height: max(maxY - minY, 0))
        }
    }

    /// The gap at `point`, if any. `slop` widens the hit area into the cells so a grid with no
    /// gap can still be grabbed.
    public func divider(at point: CGPoint, in area: CGRect, gap: CGFloat, slop: CGFloat = 4, scope: Scope) -> Divider? {
        let frames = cellFrames(in: area, gap: gap)
        for i in cells.indices {
            for j in cells.indices where i != j {
                if abs(cells[i].maxX - cells[j].minX) < Self.epsilon,
                   point.x >= frames[i].maxX - slop, point.x <= frames[j].minX + slop,
                   point.y >= max(frames[i].minY, frames[j].minY), point.y <= min(frames[i].maxY, frames[j].maxY) {
                    return divider(.vertical, i, j, scope: scope)
                }
                if abs(cells[i].maxY - cells[j].minY) < Self.epsilon,
                   point.y >= frames[i].maxY - slop, point.y <= frames[j].minY + slop,
                   point.x >= max(frames[i].minX, frames[j].minX), point.x <= min(frames[i].maxX, frames[j].maxX) {
                    return divider(.horizontal, i, j, scope: scope)
                }
            }
        }
        return nil
    }

    private func divider(_ axis: Divider.Axis, _ i: Int, _ j: Int, scope: Scope) -> Divider {
        guard scope == .line else { return Divider(axis: axis, before: [i], after: [j]) }
        let edge = axis == .vertical ? cells[i].maxX : cells[i].maxY
        let before = cells.indices.filter { abs((axis == .vertical ? cells[$0].maxX : cells[$0].maxY) - edge) < Self.epsilon }
        let after = cells.indices.filter { abs((axis == .vertical ? cells[$0].minX : cells[$0].minY) - edge) < Self.epsilon }
        return Divider(axis: axis, before: before, after: after)
    }

    /// The empty strip a divider occupies, at least `minimumThickness` across.
    public func frame(of divider: Divider, in area: CGRect, gap: CGFloat, minimumThickness: CGFloat = 0) -> CGRect {
        guard let first = divider.before.first, let second = divider.after.first else { return .null }
        let frames = cellFrames(in: area, gap: gap)
        let vertical = divider.axis == .vertical
        // Across the gap, the strip runs from the cells before it to the cells after it.
        let start = vertical ? frames[first].maxX : frames[first].maxY
        let end = vertical ? frames[second].minX : frames[second].minY
        let thickness = max(end - start, minimumThickness)
        // Along it, a pair spans only where both cells overlap and a line spans all of its cells.
        let sides = (divider.before + divider.after).map { frames[$0] }
        let lows = sides.map { vertical ? $0.minY : $0.minX }
        let highs = sides.map { vertical ? $0.maxY : $0.maxX }
        let isPair = divider.before.count == 1 && divider.after.count == 1
        let low = (isPair ? lows.max() : lows.min()) ?? 0
        let high = (isPair ? highs.min() : highs.max()) ?? 0
        let middle = (start + end) / 2 - thickness / 2
        return vertical
            ? CGRect(x: middle, y: low, width: thickness, height: high - low)
            : CGRect(x: low, y: middle, width: high - low, height: thickness)
    }

    public func cells(beside divider: Divider) -> [Int] {
        divider.before + divider.after
    }

    /// Moves a divider so its gap is centred on `position` (an x for vertical gaps, a y for
    /// horizontal ones). No cell on either side shrinks below `minimum` points, or below its
    /// entry in `minimums`, the smallest size the window in it accepts. Within `snap` points of
    /// another cell's edge or an even grid line that respects those limits, the gap lines up
    /// with it exactly. Returns whether it snapped.
    @discardableResult
    public mutating func move(_ divider: Divider, to position: CGFloat, in area: CGRect, gap: CGFloat,
                              minimum: CGFloat = 200, minimums: [Int: CGSize] = [:], snap: CGFloat = 0) -> Bool {
        let vertical = divider.axis == .vertical
        let origin = vertical ? area.minX : area.minY
        let span = Double((vertical ? area.width : area.height) - gap)
        guard span > 0 else { return false }
        func smallest(_ cell: Int) -> Double {
            let window = minimums[cell].map { vertical ? $0.width : $0.height } ?? 0
            return Double(max(minimum, window) + gap) / span
        }
        let lower = divider.before.map { (vertical ? cells[$0].minX : cells[$0].minY) + smallest($0) }.max() ?? 0
        let upper = divider.after.map { (vertical ? cells[$0].maxX : cells[$0].maxY) - smallest($0) }.min() ?? 1
        var edge = Double(position - origin - gap / 2) / span

        var snapped = false
        if snap > 0, lower <= upper,
           let target = snapTarget(for: edge, divider: divider, within: Double(snap) / span, in: lower...upper) {
            edge = target
            snapped = true
        }
        edge = lower > upper ? (lower + upper) / 2 : min(max(edge, lower), upper)
        for index in divider.before {
            if vertical { cells[index].maxX = edge } else { cells[index].maxY = edge }
        }
        for index in divider.after {
            if vertical { cells[index].minX = edge } else { cells[index].minY = edge }
        }
        return snapped
    }

    /// The nearest edge worth lining up with, either another cell's edge on the same axis or an
    /// even split of the layout, so a dragged gap can find its way back to equal sizes.
    private func snapTarget(for edge: Double, divider: Divider, within distance: Double, in bounds: ClosedRange<Double>) -> Double? {
        let vertical = divider.axis == .vertical
        let moving = Set(divider.before + divider.after)
        let count = vertical ? layout.columns : layout.rows
        var candidates = (1..<max(count, 1)).map { Double($0) / Double(count) }
        for index in cells.indices where !moving.contains(index) {
            let cell = cells[index]
            candidates += vertical ? [cell.minX, cell.maxX] : [cell.minY, cell.maxY]
        }
        return candidates
            .filter { bounds.contains($0) && abs($0 - edge) <= distance }
            .min { abs($0 - edge) < abs($1 - edge) }
    }

    private static func point(_ fraction: Double, _ origin: CGFloat, _ length: CGFloat, _ gap: CGFloat) -> CGFloat {
        origin + gap / 2 + CGFloat(fraction) * (length - gap)
    }
}

extension TileGrid: Codable {
    private enum CodingKeys: String, CodingKey { case layout, cells }

    /// Saved cells that don't fit the layout fall back to equal ones.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(try container.decode(TileLayout.self, forKey: .layout))
        if let cells = try container.decodeIfPresent([Edges].self, forKey: .cells), cells.count == layout.cellCount {
            self.cells = cells
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(layout, forKey: .layout)
        try container.encode(cells, forKey: .cells)
    }
}

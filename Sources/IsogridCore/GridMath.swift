import CoreGraphics

/// Matching windows to cells, in a top-left-origin space.
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

    /// Pairs windows with the cell they occupy, meaning the centre is inside the cell and every
    /// edge is within `tolerance`, which allows for apps that round sizes or enforce a minimum.
    public static func match(windows: [CGRect], to cells: [CGRect], tolerance: CGFloat = 24) -> [Int?] {
        windows.map { window in
            cells.firstIndex { cell in
                cell.contains(CGPoint(x: window.midX, y: window.midY))
                    && abs(window.minX - cell.minX) <= tolerance && abs(window.maxX - cell.maxX) <= tolerance
                    && abs(window.minY - cell.minY) <= tolerance && abs(window.maxY - cell.maxY) <= tolerance
            }
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

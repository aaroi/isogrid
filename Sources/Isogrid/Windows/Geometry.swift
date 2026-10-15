import CoreGraphics

extension CGRect {
    nonisolated var center: CGPoint { CGPoint(x: midX, y: midY) }

    /// Equal within `tolerance` points on every edge. Apps round sizes, so frames read back
    /// from Accessibility are rarely exactly what was set.
    nonisolated func isClose(to other: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
}

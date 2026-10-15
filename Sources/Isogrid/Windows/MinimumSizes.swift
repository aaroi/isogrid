import CoreGraphics
import IsogridCore

/// The smallest size each window has shown it accepts, learned from how it answers resizes.
/// A side that has never stopped short is 0.
enum MinimumSizes {
    private static var sizes: [CGWindowID: CGSize] = [:]

    static subscript(id: CGWindowID) -> CGSize? { sizes[id] }

    /// Updates what is known from the frame a window was given and the size it kept.
    static func record(_ move: Tiler.Move, kept: CGSize) {
        let id = move.window.windowID
        let known = sizes[id] ?? .zero
        let learned = CGSize(width: MinimumSize.update(known.width, asked: move.frame.width, kept: kept.width),
                             height: MinimumSize.update(known.height, asked: move.frame.height, kept: kept.height))
        sizes[id] = learned == .zero ? nil : learned
    }

    static func prune(keeping alive: Set<CGWindowID>) {
        sizes = sizes.filter { alive.contains($0.key) }
    }
}

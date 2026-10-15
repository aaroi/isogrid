import CoreGraphics

/// The smallest size each window accepts. macOS has no API for it, so it is learned when a
/// window keeps a larger size than it was given, and forgotten once it accepts a smaller one.
/// A side that has never refused is 0.
enum MinimumSizes {
    private static var sizes: [CGWindowID: CGSize] = [:]

    static subscript(id: CGWindowID) -> CGSize? { sizes[id] }

    /// Updates what is known from the frames windows were given and the sizes they kept, for
    /// those that kept a different one.
    static func record(_ moves: [Tiler.Move], kept: [CGWindowID: CGSize]) {
        for move in moves {
            let id = move.window.windowID
            let asked = move.frame.size
            let size = kept[id] ?? asked
            let known = sizes[id] ?? .zero
            let learned = CGSize(width: side(known.width, asked: asked.width, kept: size.width),
                                 height: side(known.height, asked: asked.height, kept: size.height))
            sizes[id] = learned == .zero ? nil : learned
        }
    }

    static func prune(keeping alive: Set<CGWindowID>) {
        sizes = sizes.filter { alive.contains($0.key) }
    }

    /// A window that stayed larger than asked is at its minimum; one that went smaller than the
    /// known minimum has outgrown it, as when an app hides a sidebar.
    private static func side(_ known: CGFloat, asked: CGFloat, kept: CGFloat) -> CGFloat {
        if kept > asked + 2 { return kept }
        return kept < known - 2 ? 0 : known
    }
}

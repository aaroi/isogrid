import CoreGraphics

/// What a window's answer to a resize says about how small it can get, one side at a time.
/// macOS doesn't tell other apps a window's minimum size, so it is learned from what windows do.
public enum MinimumSize {
    /// How far a window can land from the size it was given just by rounding, as terminals do
    /// to whole characters. Stopping further short than this means it has reached its minimum.
    public static let slack: CGFloat = 12

    /// The minimum known for one side after a window given `asked` points kept `kept`, starting
    /// from `known`. 0 means unknown.
    public static func update(_ known: CGFloat, asked: CGFloat, kept: CGFloat) -> CGFloat {
        if kept > asked + slack { return kept }
        // Smaller than the minimum seen before, as when an app hides a sidebar.
        return kept < known - slack ? 0 : known
    }
}

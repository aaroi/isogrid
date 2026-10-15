import AppKit

/// A rounded pane of glass. On macOS 26 it is Liquid Glass; earlier systems get a
/// behind-window blur. A soft sheen fading down from the top edge gives it depth.
final class GlassPane: NSView {
    enum Kind {
        /// The drop target, clear glass tinted with the accent colour so the window under it shows through.
        case target
        /// A frosted pane with the app's icon that stands in for a window while it moves.
        case standIn
        /// The grab handle in a gap.
        case handle
    }

    let kind: Kind
    private let glass: NSView
    private let sheen = CAGradientLayer()
    private let icon = NSImageView()
    private var frosted = false

    var cornerRadius: CGFloat {
        didSet { applyCornerRadius() }
    }

    init(kind: Kind) {
        self.kind = kind
        cornerRadius = kind == .handle ? 3 : 16

        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.style = kind == .standIn ? .regular : .clear
            self.glass = glass
        } else {
            let blur = NSVisualEffectView()
            blur.material = kind == .target ? .selection : .hudWindow
            blur.blendingMode = .behindWindow
            blur.state = .active
            self.glass = blur
        }
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerCurve = .continuous
        glass.frame = bounds
        glass.autoresizingMask = [.width, .height]
        addSubview(glass)

        sheen.cornerCurve = .continuous
        // Layer space is y-up here, so the sheen starts at the top edge.
        sheen.startPoint = CGPoint(x: 0.5, y: 1)
        sheen.endPoint = CGPoint(x: 0.5, y: 0)
        layer?.addSublayer(sheen)

        if kind == .standIn {
            icon.imageScaling = .scaleProportionallyUpOrDown
            icon.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
            icon.shadow = {
                let shadow = NSShadow()
                shadow.shadowColor = .black.withAlphaComponent(0.3)
                shadow.shadowBlurRadius = 10
                shadow.shadowOffset = NSSize(width: 0, height: -3)
                return shadow
            }()
            addSubview(icon)
        }
        applyStyle()
        applyCornerRadius()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func setIcon(_ image: NSImage?) {
        icon.image = image
        let side: CGFloat = 56
        icon.frame = CGRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side)
    }

    /// The target turns to frosted glass on drop, hiding the window as it snaps into place under it.
    func setFrosted(_ frosted: Bool) {
        guard frosted != self.frosted else { return }
        self.frosted = frosted
        if #available(macOS 26, *), let glass = glass as? NSGlassEffectView {
            glass.style = frosted || kind == .standIn ? .regular : .clear
        }
        applyStyle()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sheen.frame = bounds
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyStyle()
    }

    private func applyStyle() {
        let accent = NSColor.controlAccentColor
        let white = NSColor.white
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        switch kind {
        case .target:
            if #available(macOS 26, *), let glass = glass as? NSGlassEffectView {
                glass.tintColor = accent.withAlphaComponent(frosted ? 0.45 : 0.3)
            }
            sheen.colors = [accent.withAlphaComponent(0.28).cgColor, accent.withAlphaComponent(0.08).cgColor, white.withAlphaComponent(0.06).cgColor]
            sheen.locations = [0, 0.55, 1]
            layer?.borderColor = accent.withAlphaComponent(0.9).cgColor
            layer?.borderWidth = 1.5
        case .standIn:
            sheen.colors = [white.withAlphaComponent(0.22).cgColor, white.withAlphaComponent(0.05).cgColor, NSColor.clear.cgColor]
            sheen.locations = [0, 0.4, 1]
            layer?.borderColor = white.withAlphaComponent(0.28).cgColor
            layer?.borderWidth = 1
        case .handle:
            sheen.colors = [white.withAlphaComponent(0.9).cgColor, white.withAlphaComponent(0.7).cgColor]
            sheen.locations = [0, 1]
            layer?.borderColor = NSColor.black.withAlphaComponent(0.18).cgColor
            layer?.borderWidth = 0.5
        }
        CATransaction.commit()
    }

    private func applyCornerRadius() {
        layer?.cornerRadius = cornerRadius
        sheen.cornerRadius = cornerRadius
        if #available(macOS 26, *), let glass = glass as? NSGlassEffectView {
            glass.cornerRadius = cornerRadius
        } else {
            glass.wantsLayer = true
            glass.layer?.cornerRadius = cornerRadius
            glass.layer?.cornerCurve = .continuous
            glass.layer?.masksToBounds = true
        }
    }
}

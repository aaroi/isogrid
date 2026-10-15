import AppKit
import QuartzCore

/// Apple's spring parameters: `response` is roughly how long the motion takes, in seconds;
/// `damping` 1 settles without overshoot, lower values overshoot slightly.
struct Spring {
    var response: Double
    var damping: Double

    /// The drop target following the pointer from cell to cell.
    static let track = Spring(response: 0.28, damping: 0.9)
    /// Window stand-ins flying to their new cells.
    static let fly = Spring(response: 0.46, damping: 0.86)
}

/// Animates view frames with springs, stepped on the display's refresh. Retargeting keeps the
/// current velocity, so motion can be redirected mid-flight without a jump in speed.
final class Animator: NSObject {
    private final class Motion {
        let view: NSView
        var value: SIMD4<Double>
        var velocity = SIMD4<Double>(repeating: 0)
        var target: SIMD4<Double>
        var spring: Spring

        init(view: NSView, target: CGRect, spring: Spring) {
            self.view = view
            value = SIMD4(view.frame)
            self.target = SIMD4(target)
            self.spring = spring
        }

        /// Semi-implicit Euler in small substeps, which stays stable at any frame rate.
        func step(_ dt: Double) -> Bool {
            let stiffness = pow(2 * .pi / spring.response, 2)
            let friction = 4 * .pi * spring.damping / spring.response
            var remaining = dt
            while remaining > 0 {
                let h = min(remaining, 1.0 / 480)
                velocity += (-stiffness * (value - target) - friction * velocity) * h
                value += velocity * h
                remaining -= h
            }
            let settled = largest(value - target) < 0.2 && largest(velocity) < 4
            if settled {
                value = target
                velocity = .zero
            }
            return settled
        }
    }

    private let host: NSView
    private var link: CADisplayLink?
    private var motions: [ObjectIdentifier: Motion] = [:]
    private var lastTimestamp: CFTimeInterval?
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    init(host: NSView) {
        self.host = host
    }

    var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    func animate(_ view: NSView, to frame: CGRect, with spring: Spring) {
        guard !reduceMotion else { return set(view, frame) }
        let id = ObjectIdentifier(view)
        if let motion = motions[id] {
            motion.target = SIMD4(frame)
            motion.spring = spring
        } else {
            motions[id] = Motion(view: view, target: frame, spring: spring)
        }
        start()
    }

    /// Jumps to `frame` and drops any running motion, for 1:1 tracking under the pointer.
    func set(_ view: NSView, _ frame: CGRect) {
        motions[ObjectIdentifier(view)] = nil
        view.frame = frame
    }

    /// Returns once every running motion has settled.
    func settled() async {
        guard !motions.isEmpty else { return }
        await withCheckedContinuation { idleWaiters.append($0) }
    }

    private func start() {
        if link == nil {
            let link = host.displayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            self.link = link
        }
        link?.isPaused = false
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = min(lastTimestamp.map { now - $0 } ?? 1.0 / 120, 1.0 / 30)
        lastTimestamp = now
        for (id, motion) in motions {
            let settled = motion.step(dt)
            motion.view.frame = CGRect(motion.value)
            if settled { motions[id] = nil }
        }
        if motions.isEmpty {
            link.isPaused = true
            lastTimestamp = nil
            let waiters = idleWaiters
            idleWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
    }
}

/// Fades with AppKit's implicit animation, which runs in the render server and keeps going
/// even while the main thread is busy.
func fade(_ views: [NSView], to alpha: CGFloat, duration: TimeInterval, completion: (@MainActor () -> Void)? = nil) {
    NSAnimationContext.runAnimationGroup { context in
        context.duration = duration
        context.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
        context.allowsImplicitAnimation = true
        for view in views { view.animator().alphaValue = alpha }
    } completionHandler: {
        MainActor.assumeIsolated { completion?() }
    }
}

private func largest(_ v: SIMD4<Double>) -> Double {
    max(max(abs(v.x), abs(v.y)), max(abs(v.z), abs(v.w)))
}

private extension SIMD4 where Scalar == Double {
    init(_ rect: CGRect) {
        self.init(Double(rect.minX), Double(rect.minY), Double(rect.width), Double(rect.height))
    }
}

private extension CGRect {
    init(_ v: SIMD4<Double>) {
        self.init(x: v.x, y: v.y, width: max(v.z, 0), height: max(v.w, 0))
    }
}

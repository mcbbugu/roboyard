import AppKit
import QuartzCore

@MainActor
final class RobotIconView: NSView {
    var isActive = false {
        didSet { alphaValue = isActive ? 1 : 0.55; needsDisplay = true }
    }
    var charging = false { didSet { needsDisplay = true } }
    var parked = 0 { didSet { needsDisplay = true } }

    private var lid: CGFloat = 0
    private var timer: Timer?
    private var highlighted = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        alphaValue = 0.55
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopClock() } else { startClock() }
    }

    private func startClock() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopClock() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let on = (superview as? NSStatusBarButton)?.isHighlighted ?? false
        if on != highlighted {
            highlighted = on
            needsDisplay = true
        }
        charging = Critters.shared.chargingCount > 0
        parked = Critters.shared.chargingCount
        if let window {
            let frame = window.convertToScreen(convert(bounds, to: nil))
            Critters.shared.nestAnchor = CGPoint(x: frame.midX, y: frame.minY)
        }
        let next = RobotMark.lid()
        if abs(next - lid) > 0.01 || charging {
            lid = next
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let pulse = charging ? 0.55 + 0.45 * sin(CACurrentMediaTime() * 4) : 1
        let color = (highlighted ? NSColor.white : NSColor.labelColor).withAlphaComponent(pulse)
        let glyph: CGFloat = 16
        let origin = CGPoint(x: ((bounds.width - glyph) / 2).rounded(.toNearestOrAwayFromZero),
                             y: ((bounds.height - glyph) / 2).rounded(.toNearestOrAwayFromZero))
        RobotMark.draw(in: CGRect(x: origin.x, y: origin.y, width: glyph, height: glyph), lid: lid, ink: color)
        if parked > 0 {
            let dot = NSBezierPath(ovalIn: CGRect(x: bounds.maxX - 6, y: bounds.maxY - 6, width: 4, height: 4))
            NSColor.systemGreen.withAlphaComponent(charging ? pulse : 0.9).setFill()
            dot.fill()
        }
    }
}

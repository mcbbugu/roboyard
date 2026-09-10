import AppKit
import QuartzCore

enum RobotMark {
    static func lid(at time: CFTimeInterval = CACurrentMediaTime(), cycle: Double = 2.05) -> CGFloat {
        let t = time.truncatingRemainder(dividingBy: cycle)
        if t < 0.09 {
            let u = CGFloat(t / 0.09)
            return u * u * (3 - 2 * u)
        }
        if t < 0.16 { return 1 }
        if t < 0.26 {
            let u = CGFloat((t - 0.16) / 0.10)
            let s = u * u * (3 - 2 * u)
            return 1 - s
        }
        return 0
    }

    static func draw(in g: CGRect, lid: CGFloat, ink: NSColor = .labelColor, halo: NSColor? = nil) {
        let s = min(g.width, g.height)
        let line = max(1.2, s / 14)
        if let halo {
            halo.set()
            stroke(in: g, line: line + 2.6)
            NSColor.white.set()
            stroke(in: g, line: line + 1.1)
            NSColor.black.set()
            stroke(in: g, line: line)
            eyesOverlay(in: g, lid: lid)
            return
        }
        ink.set()
        stroke(in: g, line: line)
        eyes(in: g, lid: lid)
    }

    static func drawBot(in g: CGRect, lid: CGFloat, gait: CGFloat, speed: CGFloat = 40, sit: CGFloat = 0) {
        let drop = sit * g.height * 0.16
        let box = g.offsetBy(dx: 0, dy: -drop)
        let bob = speed > 12 ? sin(gait * .pi * 2) * g.height * 0.04 : 0
        let body = box.offsetBy(dx: 0, dy: bob)
        draw(in: body, lid: lid, ink: .white, halo: .black)
        legs(in: body, gait: gait, speed: speed, sit: sit)
    }

    private static func legs(in g: CGRect, gait: CGFloat, speed: CGFloat, sit: CGFloat) {
        let s = min(g.width, g.height)
        let w = max(0.9, s / 15)
        let plant = speed < 10
        let amp = plant ? 0 : min(1, speed / 55)
        let hips: [(CGFloat, CGFloat, CGFloat)] = [
            (-1, 0.20, 0),
            (1, 0.20, .pi),
            (-1, 0.02, .pi),
            (1, 0.02, 0),
        ]
        let ground = g.minY + g.height * 0.02 - sit * s * 0.04
        for (side, yOff, phase0) in hips {
            let phase = gait * .pi * 2 + phase0
            let swing = sin(phase)
            let lift = max(0, swing) * s * 0.14 * amp
            let stride = swing * s * 0.11 * amp
            let hip = CGPoint(x: g.midX + side * g.width * 0.15, y: g.minY + g.height * (0.16 + yOff))
            let knee = CGPoint(
                x: hip.x + side * s * 0.09 + stride * 0.35,
                y: hip.y - s * 0.07 + lift * 0.45
            )
            let foot = CGPoint(
                x: hip.x + side * s * (0.12 + sit * 0.06) + stride,
                y: max(ground, hip.y - s * 0.16 + lift)
            )
            bone([hip, knee, foot], width: w)
        }
    }

    private static func bone(_ pts: [CGPoint], width: CGFloat) {
        guard pts.count >= 2 else { return }
        let path = NSBezierPath()
        path.move(to: pts[0])
        for p in pts.dropFirst() { path.line(to: p) }
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        NSColor.black.setStroke()
        path.lineWidth = width + 1.5
        path.stroke()
        NSColor.white.setStroke()
        path.lineWidth = width
        path.stroke()
    }

    private static func eyesOverlay(in g: CGRect, lid: CGFloat) {
        let head = CGRect(x: g.minX + g.width * 0.14, y: g.minY + g.height * 0.32, width: g.width * 0.72, height: g.height * 0.60)
        let open = max(1.4, g.width * 0.13)
        let eyeH = max(0.7, open * (1 - lid))
        let eyeY = head.midY - eyeH / 2
        let gap = g.width * 0.20
        let leftX = head.midX - gap / 2 - open / 2
        let rightX = head.midX + gap / 2 - open / 2
        for x in [leftX, rightX] {
            let r = CGRect(x: x, y: eyeY, width: open, height: eyeH)
            NSColor.white.setFill()
            NSBezierPath(roundedRect: r, xRadius: eyeH / 2, yRadius: eyeH / 2).fill()
            NSColor.black.setStroke()
            let p = NSBezierPath(roundedRect: r, xRadius: eyeH / 2, yRadius: eyeH / 2)
            p.lineWidth = 0.8
            p.stroke()
        }
    }

    private static func stroke(in g: CGRect, line: CGFloat) {
        let head = CGRect(x: g.minX + g.width * 0.14, y: g.minY + g.height * 0.32, width: g.width * 0.72, height: g.height * 0.60)
        let headPath = NSBezierPath(roundedRect: head, xRadius: g.width * 0.20, yRadius: g.height * 0.20)
        headPath.lineWidth = line
        headPath.lineJoinStyle = .round
        headPath.stroke()

        let body = CGRect(x: g.midX - g.width * 0.21, y: g.minY + g.height * 0.08, width: g.width * 0.42, height: g.height * 0.22)
        let bodyPath = NSBezierPath(roundedRect: body, xRadius: g.width * 0.09, yRadius: g.height * 0.09)
        bodyPath.lineWidth = line
        bodyPath.stroke()

        let neck = NSBezierPath()
        neck.lineWidth = line
        neck.lineCapStyle = .round
        neck.move(to: CGPoint(x: g.midX, y: body.maxY))
        neck.line(to: CGPoint(x: g.midX, y: head.minY))
        neck.stroke()
    }

    private static func eyes(in g: CGRect, lid: CGFloat) {
        let head = CGRect(x: g.minX + g.width * 0.14, y: g.minY + g.height * 0.32, width: g.width * 0.72, height: g.height * 0.60)
        let open = max(1.4, g.width * 0.13)
        let eyeH = max(0.7, open * (1 - lid))
        let eyeY = head.midY - eyeH / 2
        let gap = g.width * 0.20
        let leftX = head.midX - gap / 2 - open / 2
        let rightX = head.midX + gap / 2 - open / 2
        NSBezierPath(roundedRect: CGRect(x: leftX, y: eyeY, width: open, height: eyeH), xRadius: eyeH / 2, yRadius: eyeH / 2).fill()
        NSBezierPath(roundedRect: CGRect(x: rightX, y: eyeY, width: open, height: eyeH), xRadius: eyeH / 2, yRadius: eyeH / 2).fill()
    }
}

@MainActor
func makeOverlay(size: NSSize, level: NSWindow.Level = .floating) -> NSPanel {
    let panel = NSPanel(
        contentRect: NSRect(origin: .zero, size: size),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    panel.isFloatingPanel = true
    panel.hidesOnDeactivate = false
    panel.hasShadow = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.ignoresMouseEvents = true
    panel.becomesKeyOnlyIfNeeded = true
    panel.level = level
    panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
    panel.sharingType = .readOnly
    panel.animationBehavior = .none
    panel.canHide = false
    return panel
}

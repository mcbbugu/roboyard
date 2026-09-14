import AppKit
import QuartzCore

enum RobotMark {
    /// Fixed sRGB palette so accents test exact and look the same on any wallpaper.
    static func accent(for group: String) -> NSColor {
        switch group {
        case "NT": NSColor(srgbRed: 0.62, green: 0.50, blue: 0.95, alpha: 1)
        case "NF": NSColor(srgbRed: 0.97, green: 0.52, blue: 0.70, alpha: 1)
        case "SJ": NSColor(srgbRed: 0.30, green: 0.78, blue: 0.72, alpha: 1)
        case "SP": NSColor(srgbRed: 1.00, green: 0.62, blue: 0.25, alpha: 1)
        default: NSColor(srgbRed: 0.60, green: 0.60, blue: 0.65, alpha: 1)
        }
    }

    static func energyTint(_ energy: Double) -> NSColor {
        if energy <= ChargeLaw.goHomeBelow { NSColor(srgbRed: 0.95, green: 0.30, blue: 0.30, alpha: 1) }
        else if energy <= ChargeLaw.talkBelow { NSColor(srgbRed: 1.00, green: 0.62, blue: 0.20, alpha: 1) }
        else if energy >= ChargeLaw.emergeAbove { NSColor(srgbRed: 0.35, green: 0.80, blue: 0.45, alpha: 1) }
        else { NSColor(white: 1, alpha: 0.8) }
    }

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

    static func drawBot(in g: CGRect, lid: CGFloat, gait: CGFloat, speed: CGFloat = 40, sit: CGFloat = 0,
                        tired: CGFloat = 0, glow: Bool = false,
                        accent: NSColor? = nil, stage: Int = 0, energy: Double = 1) {
        let drop = sit * g.height * 0.16
        let box = g.offsetBy(dx: 0, dy: -drop)
        let bob = speed > 12 ? sin(gait * .pi * 2) * g.height * 0.04 * (1 - tired) : 0
        let body = box.offsetBy(dx: 0, dy: bob)
        let shut = max(lid, tired * 0.55)
        antenna(in: body, stage: stage, accent: accent)
        let ink: NSColor = tired > 0.45 ? NSColor.white.withAlphaComponent(0.72) : .white
        draw(in: body, lid: shut, ink: ink, halo: glow ? NSColor.systemYellow.withAlphaComponent(0.9) : .black)
        legs(in: body, gait: gait, speed: speed * (1 - tired * 0.5), sit: sit)
        if let accent { cheeks(in: body, accent: accent) }
        // Full charge stays clean (icons, previews); the bar appears once drained.
        if energy < 0.995 { energyBar(in: body, energy: energy) }
    }

    private static func headRect(in g: CGRect) -> CGRect {
        CGRect(x: g.minX + g.width * 0.14, y: g.minY + g.height * 0.32,
               width: g.width * 0.72, height: g.height * 0.60)
    }

    /// Growth antennae: curious nub, thoughtful stalk, awakened spark.
    /// Drawn before the body so the head stroke overlaps the base.
    private static func antenna(in g: CGRect, stage: Int, accent: NSColor?) {
        guard stage >= 1 else { return }
        let s = min(g.width, g.height)
        let head = headRect(in: g)
        let base = CGPoint(x: g.midX, y: head.maxY - s * 0.02)
        let tipColor = accent ?? NSColor.white
        if stage == 1 {
            let dot = CGPoint(x: g.midX, y: head.maxY + s * 0.02)
            dotDot(at: dot, radius: s * 0.035, color: tipColor)
            return
        }
        let tip = CGPoint(x: g.midX, y: head.maxY + s * 0.11)
        bone([base, tip], width: max(1.0, s / 24))
        dotDot(at: tip, radius: s * 0.04, color: tipColor)
        if stage >= 3 {
            let len = s * 0.055
            let spark = NSBezierPath()
            spark.move(to: CGPoint(x: tip.x - len, y: tip.y)); spark.line(to: CGPoint(x: tip.x + len, y: tip.y))
            spark.move(to: CGPoint(x: tip.x, y: tip.y - len)); spark.line(to: CGPoint(x: tip.x, y: tip.y + len))
            spark.lineCapStyle = .round
            tipColor.setStroke()
            spark.lineWidth = max(1.0, s / 30)
            spark.stroke()
        }
    }

    private static func cheeks(in g: CGRect, accent: NSColor) {
        let head = headRect(in: g)
        let open = max(1.4, g.width * 0.13)
        let cy = head.midY - open * 0.5 - g.height * 0.055
        let r = open * 0.42
        for x in [head.midX - g.width * 0.10, head.midX + g.width * 0.10] {
            accent.withAlphaComponent(0.85).setFill()
            NSBezierPath(ovalIn: CGRect(x: x - r, y: cy - r, width: r * 2, height: r * 2)).fill()
        }
    }

    /// Thin charge bar under the feet; same thresholds as the warehouse meter.
    private static func energyBar(in g: CGRect, energy: Double) {
        let w = g.width * 0.52
        let h = max(1.6, g.height * 0.05)
        let bar = CGRect(x: g.midX - w / 2, y: g.minY - h - g.height * 0.03, width: w, height: h)
        NSColor.black.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: bar, xRadius: h / 2, yRadius: h / 2).fill()
        let e = min(1, max(0, energy))
        if e > 0.01 {
            energyTint(e).setFill()
            NSBezierPath(roundedRect: CGRect(x: bar.minX, y: bar.minY, width: bar.width * e, height: bar.height),
                          xRadius: h / 2, yRadius: h / 2).fill()
        }
    }

    private static func dotDot(at p: CGPoint, radius: CGFloat, color: NSColor) {
        NSColor.black.setFill()
        NSBezierPath(ovalIn: CGRect(x: p.x - radius - 0.8, y: p.y - radius - 0.8,
                                    width: (radius + 0.8) * 2, height: (radius + 0.8) * 2)).fill()
        color.setFill()
        NSBezierPath(ovalIn: CGRect(x: p.x - radius, y: p.y - radius,
                                    width: radius * 2, height: radius * 2)).fill()
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

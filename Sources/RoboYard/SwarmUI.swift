import AppKit

@MainActor
final class SwarmLayer {
    let panel: NSPanel
    let canvas: SwarmCanvas
    let home: NSRect
    let index: Int
    init(panel: NSPanel, canvas: SwarmCanvas, home: NSRect, index: Int) {
        self.panel = panel
        self.canvas = canvas
        self.home = home
        self.index = index
    }
}

@MainActor
final class SwarmCanvas: NSView {
    var bots: [Bot] = []
    var lid: CGFloat = 0
    var index = 0
    var highlights: Set<Int> = []

    override var isOpaque: Bool { false }
    override var wantsDefaultClipping: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let window, let ctx = NSGraphicsContext.current?.cgContext else { return }
        for bot in bots {
            let size = bot.bodySize
            let local = convert(window.convertPoint(fromScreen: bot.point), from: nil)
            let g = CGRect(x: local.x - size / 2, y: local.y - size / 2, width: size, height: size)
            ctx.saveGState()
            ctx.translateBy(x: local.x, y: local.y)
            ctx.rotate(by: bot.angle)
            ctx.translateBy(x: -local.x, y: -local.y)
            RobotMark.drawBot(in: g, lid: lid, gait: bot.gait, speed: bot.speed, sit: bot.sit,
                              tired: 1 - bot.limp, glow: highlights.contains(bot.id),
                              accent: RobotMark.accent(for: bot.mbti.group),
                              stage: bot.memory.stage().rawValue, energy: bot.energy)
            ctx.restoreGState()
        }
    }
}

@MainActor
final class Bubble {
    let panel: NSPanel
    let view: BubbleView
    let until: CFTimeInterval
    weak var bot: Bot?
    init(panel: NSPanel, view: BubbleView, until: CFTimeInterval, bot: Bot?) {
        self.panel = panel
        self.view = view
        self.until = until
        self.bot = bot
    }
    func kill() { panel.orderOut(nil) }
}

@MainActor
final class BubbleView: NSView {
    let text: String
    var fitting: NSSize {
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        let w = (text as NSString).size(withAttributes: [.font: font]).width
        return NSSize(width: ceil(w) + 16, height: 22)
    }

    init(text: String) {
        self.text = text
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8)
        NSColor.black.withAlphaComponent(0.72).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.18).setStroke()
        path.lineWidth = 1
        path.stroke()
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        let p = NSMutableParagraphStyle()
        p.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
            .paragraphStyle: p,
        ]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let y = ((bounds.height - textSize.height) / 2).rounded(.toNearestOrAwayFromZero)
        (text as NSString).draw(
            in: CGRect(x: 0, y: y, width: bounds.width, height: textSize.height),
            withAttributes: attrs
        )
    }
}

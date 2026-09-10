import AppKit
import QuartzCore

@MainActor
final class Critters: NSObject {
    static let shared = Critters()

    static let crawlKey = "critter.crawl"
    static let countKey = "critter.count"
    static let countChoices = [4, 8, 12, 16, 24, 32]

    var crawlOn: Bool {
        get { UserDefaults.standard.object(forKey: Self.crawlKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.crawlKey); apply() }
    }

    var count: Int {
        get {
            let n = UserDefaults.standard.object(forKey: Self.countKey) as? Int ?? 16
            return min(32, max(1, n))
        }
        set {
            UserDefaults.standard.set(min(32, max(1, newValue)), forKey: Self.countKey)
            resetCrawlers()
        }
    }

    private var bots: [Bot] = []
    private var swarms: [SwarmLayer] = []
    private var bubbles: [Bubble] = []
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var lastTick = CACurrentMediaTime()
    private var lastMouse = NSEvent.mouseLocation
    private var mouseWasNear = false
    private var lingerApp = ""
    private var lingerSince = CACurrentMediaTime()
    private var nextIdle = CACurrentMediaTime() + 50
    private var nextSave = CACurrentMediaTime() + 15

    func start() {
        guard observers.isEmpty else { return }
        let nc = NotificationCenter.default
        observers = [
            nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.resetCrawlers() }
            },
        ]
        apply()
        let timer = Timer(timeInterval: 1.0 / 60.0, target: self, selector: #selector(objcTick), userInfo: nil, repeats: true)
        timer.tolerance = 0.004
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    @objc private func objcTick() {
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        RobotMemoryStore.shared.save()
        clearCrawlers()
        clearBubbles()
    }

    func apply() {
        if !crawlOn {
            RobotMemoryStore.shared.save()
            clearCrawlers()
            clearBubbles()
        }
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let elapsed = max(0, min(now - lastTick, 1))
        let dt = min(elapsed, 0.033)
        lastTick = now
        tickBots(now: now, dt: dt, lid: RobotMark.lid(at: now))
        tickBubbles(now: now)
        if now >= nextSave {
            nextSave = now + 15
            RobotMemoryStore.shared.save()
        }
    }

    private func tickBots(now: CFTimeInterval, dt: CGFloat, lid: CGFloat) {
        guard crawlOn else { return }
        if bots.isEmpty { spawnSwarm() }
        scareFromMouse(now: now)
        meet(now: now)
        maybeLinger(now: now)
        maybeIdle(now: now)
        let contacts = BotPhysics.advance(bots, now: now, dt: dt)
        collide(contacts, now: now)
        for swarm in swarms {
            let box = swarm.panel.frame
            swarm.canvas.lid = lid
            for bot in swarm.canvas.bots {
                bot.home = box
                bot.clampHome()
            }
            swarm.canvas.needsDisplay = true
        }
    }

    private func scareFromMouse(now: CFTimeInterval) {
        let mouse = NSEvent.mouseLocation
        lastMouse = mouse
        var nearest: Bot?
        var nearestD: CGFloat = .greatestFiniteMagnitude
        var closeCount = 0
        for c in bots {
            let d = hypot(c.x - mouse.x, c.y - mouse.y)
            if d < nearestD {
                nearestD = d
                nearest = c
            }
            if d < 36 {
                closeCount += 1
                c.flee(from: mouse, now: now, boost: 1)
            }
        }
        let near = closeCount > 0
        if near, !mouseWasNear {
            for c in bots {
                let d = hypot(c.x - mouse.x, c.y - mouse.y)
                if d < 72 { c.flee(from: mouse, now: now, boost: 1) }
            }
            if let who = nearest {
                say(.flee, bot: who, other: nil)
            }
        }
        mouseWasNear = near
    }

    private func maybeLinger(now: CFTimeInterval) {
        let app = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
        if app != lingerApp {
            lingerApp = app
            lingerSince = now
            return
        }
        guard now - lingerSince > 42, let c = bots.randomElement(), !app.isEmpty else { return }
        lingerSince = now + 30
        say(.linger, bot: c, other: nil)
    }

    private func maybeIdle(now: CFTimeInterval) {
        guard now >= nextIdle, !mouseWasNear, let c = bots.randomElement() else { return }
        nextIdle = now + CGFloat.random(in: 55...95)
        say(c.memory.stage() == .newborn ? .idle : .reflect, bot: c, other: nil)
    }

    private func say(_ event: CritterTalk.Event, bot: Bot, other: Bot?) {
        let vibe = bot.mbti.vibe
        let otherVibe = other.map(\.mbti.vibe)
        let urgent = event == .flee || event == .chat || event == .scold
        let app = appName(at: bot.point)
        if event == .linger || event == .idle, let app, !app.isEmpty {
            bot.memory.remember(.place, subject: app, detail: "陪着人待在\(app)旁边")
        }
        let memory = bot.memory.context(kind: event.memoryKind, subject: other.map { String($0.id) })
        Task { @MainActor in
            let line = await CritterTalk.shared.speak(event: event, vibe: vibe, other: otherVibe, app: app, urgent: urgent, memory: memory)
            guard crawlOn, bots.contains(where: { $0 === bot }) else { return }
            let text = line ?? (event == .reflect ? bot.memory.reflection() : bot.mbti.fallback(event))
            if event == .reflect { bot.memory.reflect(text) }
            else { bot.memory.remember(.speech, subject: "self", detail: text) }
            if let other, bots.contains(where: { $0 === other }) {
                other.memory.remember(.speech, subject: "\(bot.id)", detail: text)
            }
            popBubble(text: text, now: CACurrentMediaTime(), bot: bot)
        }
    }

    private func meet(now: CFTimeInterval) {
        guard bots.count >= 2 else { return }
        for i in 0..<(bots.count - 1) {
            for j in (i + 1)..<bots.count {
                let a = bots[i]
                let b = bots[j]
                guard a.screenIndex == b.screenIndex, a.mbti.fits(b.mbti) else { continue }
                let d = hypot(a.x - b.x, a.y - b.y)
                guard d < a.collisionRadius + b.collisionRadius + 12, d > 8, a.canSocial(now: now), b.canSocial(now: now) else { continue }
                Bot.pairTalk(a, b, now: now)
                a.memory.meet(b.id, friendly: true)
                b.memory.meet(a.id, friendly: true)
                say(.chat, bot: a, other: b)
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_100_000_000)
                    guard crawlOn, bots.contains(where: { $0 === a }), bots.contains(where: { $0 === b }),
                          CACurrentMediaTime() < a.chatUntil else { return }
                    say(.chat, bot: b, other: a)
                }
            }
        }
    }

    private func collide(_ contacts: [BotPhysics.Contact], now: CFTimeInterval) {
        for contact in contacts {
            let a = contact.a
            let b = contact.b
            a.memory.meet(b.id, friendly: false)
            b.memory.meet(a.id, friendly: false)
            guard a.canSocial(now: now), b.canSocial(now: now), !a.mbti.fits(b.mbti) else { continue }
            Bot.pairTalk(a, b, now: now, secs: 2.4...3.8)
            say(.scold, bot: a, other: b)
        }
    }

    private func tickBubbles(now: CFTimeInterval) {
        bubbles.removeAll { bubble in
            if now >= bubble.until {
                bubble.kill()
                return true
            }
            let fade = now > bubble.until - 0.28 ? CGFloat((bubble.until - now) / 0.28) : 1
            bubble.view.alphaValue = fade
            if let bot = bubble.bot {
                bubble.panel.setFrame(bubbleFrame(size: bubble.view.fitting, bot: bot, at: nil), display: false)
            }
            return false
        }
    }

    @discardableResult
    private func popBubble(text: String, now: CFTimeInterval, bot: Bot?, at: CGPoint? = nil) -> Bubble {
        if bubbles.count > 8 {
            bubbles.removeFirst().kill()
        }
        let view = BubbleView(text: text)
        let size = view.fitting
        let panel = makeOverlay(size: size, level: .statusBar)
        view.frame = NSRect(origin: .zero, size: size)
        panel.contentView = view
        panel.setFrame(bubbleFrame(size: size, bot: bot, at: at), display: false)
        panel.orderFrontRegardless()
        let bubble = Bubble(panel: panel, view: view, until: now + 2.3, bot: bot)
        bubbles.append(bubble)
        return bubble
    }

    private func bubbleFrame(size: NSSize, bot: Bot?, at: CGPoint?) -> NSRect {
        let p: CGPoint
        let box: NSRect
        if let bot {
            p = bot.point
            box = bot.home
        } else if let at {
            p = at
            box = NSScreen.screens.first { $0.frame.contains(at) }?.visibleFrame
                ?? NSScreen.main?.visibleFrame
                ?? NSRect(origin: at, size: size)
        } else {
            return NSRect(origin: .zero, size: size)
        }
        let pad: CGFloat = 6
        let minX = box.minX + pad
        let maxX = box.maxX - pad - size.width
        let minY = box.minY + pad
        let maxY = box.maxY - pad - size.height
        var x = p.x - size.width / 2
        if maxX >= minX { x = min(max(x, minX), maxX) }
        let radius = (bot?.bodySize ?? 16) / 2
        let above = p.y + radius + 8
        let below = p.y - size.height - radius - 4
        var y: CGFloat
        if above <= maxY {
            y = above
        } else if below >= minY {
            y = below
        } else {
            y = maxY
        }
        if maxY >= minY { y = min(max(y, minY), maxY) }
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func appName(at cocoa: CGPoint) -> String? {
        let primary = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main
        guard let primary else { return NSWorkspace.shared.frontmostApplication?.localizedName }
        let q = CGPoint(x: cocoa.x, y: primary.frame.maxY - cocoa.y)
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return NSWorkspace.shared.frontmostApplication?.localizedName
        }
        for w in info {
            let layer = w[kCGWindowLayer as String] as? Int ?? 0
            if layer != 0 { continue }
            let owner = w[kCGWindowOwnerName as String] as? String ?? ""
            if owner.isEmpty || owner == "AlwaysListen" || owner == "RoboYard" { continue }
            guard let b = w[kCGWindowBounds as String] as? [String: Any],
                  let x = (b["X"] as? NSNumber)?.doubleValue,
                  let y = (b["Y"] as? NSNumber)?.doubleValue,
                  let width = (b["Width"] as? NSNumber)?.doubleValue,
                  let height = (b["Height"] as? NSNumber)?.doubleValue else { continue }
            let rect = CGRect(x: x, y: y, width: width, height: height)
            if rect.contains(q) { return owner }
        }
        return NSWorkspace.shared.frontmostApplication?.localizedName
    }

    private func spawnSwarm() {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        let want = count
        for i in 0..<want {
            let si = i % screens.count
            let screen = screens[si]
            let box = screen.visibleFrame
            let memory = RobotMemoryStore.shared.profile(id: i + 1)
            bots.append(Bot(id: i + 1, mbti: memory.mbti, home: box, screenIndex: si,
                            memory: memory))
        }
        for (si, screen) in screens.enumerated() {
            let box = screen.visibleFrame
            let canvas = SwarmCanvas(frame: NSRect(origin: .zero, size: box.size))
            canvas.clipsToBounds = false
            canvas.bots = bots.filter { $0.screenIndex == si }
            let panel = makeOverlay(size: box.size, level: .floating)
            canvas.autoresizingMask = [.width, .height]
            panel.contentView = canvas
            panel.setFrame(box, display: true)
            panel.orderFrontRegardless()
            let real = panel.frame
            for bot in canvas.bots {
                bot.home = real
                bot.clampHome()
            }
            swarms.append(SwarmLayer(panel: panel, canvas: canvas, home: real))
        }
        RobotMemoryStore.shared.save()
    }

    private func resetCrawlers() {
        RobotMemoryStore.shared.save()
        clearBubbles()
        clearCrawlers()
        if crawlOn { spawnSwarm() }
    }

    private func clearCrawlers() {
        for swarm in swarms { swarm.panel.orderOut(nil) }
        swarms = []
        bots = []
    }

    private func clearBubbles() {
        bubbles.forEach { $0.kill() }
        bubbles = []
    }
}

@MainActor
private final class SwarmLayer {
    let panel: NSPanel
    let canvas: SwarmCanvas
    let home: NSRect
    init(panel: NSPanel, canvas: SwarmCanvas, home: NSRect) {
        self.panel = panel
        self.canvas = canvas
        self.home = home
    }
}

@MainActor
final class SwarmCanvas: NSView {
    var bots: [Bot] = []
    var lid: CGFloat = 0

    override var isOpaque: Bool { false }
    override var wantsDefaultClipping: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let window else { return }
        for bot in bots {
            let size = bot.bodySize
            let local = convert(window.convertPoint(fromScreen: bot.point), from: nil)
            let g = CGRect(x: local.x - size / 2, y: local.y - size / 2, width: size, height: size)
            let ctx = NSGraphicsContext.current!.cgContext
            ctx.saveGState()
            ctx.translateBy(x: local.x, y: local.y)
            ctx.rotate(by: bot.angle)
            ctx.translateBy(x: -local.x, y: -local.y)
            RobotMark.drawBot(in: g, lid: lid, gait: bot.gait, speed: bot.speed, sit: bot.sit)
            ctx.restoreGState()
        }
    }
}

@MainActor
final class Bot {
    enum Act {
        case walk, sit, stand, flee, chat, edge
    }

    let id: Int
    let mbti: MBTI
    let memory: RobotMemory
    var home: NSRect
    let screenIndex: Int
    var x: CGFloat
    var y: CGFloat
    var heading: CGFloat
    var speed: CGFloat
    var targetHeading: CGFloat
    var targetSpeed: CGFloat
    var angle: CGFloat
    var bumpUntil: CFTimeInterval = 0
    var steerUntil: CFTimeInterval = 0
    var panicUntil: CFTimeInterval = 0
    var chatUntil: CFTimeInterval = 0
    var chatCool: CFTimeInterval = 0
    var actUntil: CFTimeInterval = 0
    var act: Act = .walk
    var edge: Int = 0
    weak var pal: Bot?
    var traveled: CGFloat = 0
    var sit: CGFloat = 0
    private var sepX: CGFloat = 0
    private var sepY: CGFloat = 0
    private let wander: CGFloat
    private let gaitScale: CGFloat
    var bodySize: CGFloat { memory.bodySize() }
    var collisionRadius: CGFloat { bodySize * 0.6 + 1.5 }

    var vx: CGFloat { cos(heading) * speed }
    var vy: CGFloat { sin(heading) * speed }
    var point: CGPoint { CGPoint(x: x, y: y) }
    var gait: CGFloat { traveled * gaitScale }
    var label: String { String(format: "%02d %@", id, mbti.code) }

    init(id: Int, mbti: MBTI, home: NSRect, screenIndex: Int,
         memory: RobotMemory? = nil) {
        self.id = id
        self.mbti = mbti
        self.memory = memory ?? RobotMemory(id: id, personality: mbti.rawValue)
        self.home = home
        self.screenIndex = screenIndex
        let inset = home.insetBy(dx: 48, dy: 48)
        x = CGFloat.random(in: inset.minX...max(inset.minX + 1, inset.maxX))
        y = CGFloat.random(in: inset.minY...max(inset.minY + 1, inset.maxY))
        heading = CGFloat.random(in: 0..<(2 * .pi))
        targetHeading = heading
        speed = CGFloat.random(in: 28...52)
        targetSpeed = speed
        angle = heading - .pi / 2
        wander = CGFloat.random(in: 0.5...1.4)
        gaitScale = 0.12
        actUntil = CACurrentMediaTime() + CGFloat.random(in: 1.5...4)
    }

    func canSocial(now: CFTimeInterval) -> Bool {
        now > panicUntil && now > chatUntil && now > chatCool && act != .flee
    }

    static func pairTalk(_ a: Bot, _ b: Bot, now: CFTimeInterval, secs: ClosedRange<CGFloat> = 3.4...5.6) {
        parkFacing(a, b)
        a.lockTalk(with: b, now: now, secs: secs)
        b.lockTalk(with: a, now: now, secs: secs)
    }

    private static func parkFacing(_ a: Bot, _ b: Bot) {
        a.face(b)
        b.face(a)
        a.speed = 0
        b.speed = 0
        a.targetSpeed = 0
        b.targetSpeed = 0
    }

    private func lockTalk(with other: Bot, now: CFTimeInterval, secs: ClosedRange<CGFloat>) {
        pal = other
        act = .chat
        chatUntil = now + CGFloat.random(in: secs)
        actUntil = chatUntil
        chatCool = chatUntil + 18
        bumpUntil = chatUntil
        speed = 0
        targetSpeed = 0
    }

    private func face(_ other: Bot) {
        heading = atan2(other.y - y, other.x - x)
        targetHeading = heading
        angle = heading - .pi / 2
    }

    func flee(from mouse: CGPoint, now: CFTimeInterval, boost: CGFloat) {
        if now >= panicUntil {
            memory.remember(.mouse, detail: "鼠标靠得太近，我跑开了")
        }
        pal = nil
        chatUntil = 0
        act = .flee
        let dx = x - mouse.x
        let dy = y - mouse.y
        let away = atan2(dy == 0 && dx == 0 ? CGFloat.random(in: -1...1) : dy, dx == 0 ? 0.01 : dx)
        heading = away
        targetHeading = away
        let burst = 90 + 140 * boost
        speed = max(speed, burst)
        targetSpeed = burst
        panicUntil = now + 0.4 + 0.35 * boost
        actUntil = panicUntil
        steerUntil = panicUntil
    }

    func separate(from others: [Bot]) {
        sepX = 0
        sepY = 0
        guard act != .chat else { return }
        var n: CGFloat = 0
        for o in others {
            if o === self || o.screenIndex != screenIndex { continue }
            let dx = x - o.x
            let dy = y - o.y
            let d = hypot(dx, dy)
            let personalSpace = collisionRadius + o.collisionRadius + 10
            if d < 0.01 || d > personalSpace { continue }
            let w = (personalSpace - d) / personalSpace
            sepX += dx / d * w
            sepY += dy / d * w
            n += 1
        }
        if n > 0 {
            sepX /= n
            sepY /= n
        }
    }

    func step(now: CFTimeInterval, dt: CGFloat) {
        if now < panicUntil {
            act = .flee
            targetSpeed = max(70, targetSpeed * (1 - dt * 0.55))
            heading = lerpAngle(heading, targetHeading, 1 - exp(-dt * 9))
            speed += (targetSpeed - speed) * (1 - exp(-dt * 10))
        } else if now < chatUntil, pal != nil {
            act = .chat
            speed = 0
            targetSpeed = 0
        } else {
            if now > actUntil { pickAct(now: now) }
            switch act {
            case .sit, .stand, .chat:
                targetSpeed = 0
                speed += (0 - speed) * (1 - exp(-dt * 6))
            case .edge:
                crawlEdge()
            case .walk, .flee:
                if now > steerUntil {
                    steerUntil = now + CGFloat.random(in: 1.6...3.8)
                    targetHeading = heading + CGFloat.random(in: -0.8...0.8)
                    targetSpeed = CGFloat.random(in: 28...58)
                }
                heading += sin(now * wander + traveled * 0.02) * 0.4 * dt
                heading = lerpAngle(heading, targetHeading, 1 - exp(-dt * 3.2))
                speed += (targetSpeed - speed) * (1 - exp(-dt * 2.4))
            }
        }
        if act == .chat {
            speed = 0
            sepX = 0
            sepY = 0
        } else {
            x += (cos(heading) * speed + sepX * 55) * dt
            y += (sin(heading) * speed + sepY * 55) * dt
            if speed > 8 { traveled += speed * dt }
            bounce()
        }
        clampHome()
        let wantSit: CGFloat = (act == .sit || act == .chat) ? 1 : 0
        sit += (wantSit - sit) * (1 - exp(-dt * 8))
        if act != .chat {
            angle = lerpAngle(angle, heading - .pi / 2, 1 - exp(-dt * 7))
        }
    }

    func clampHome() {
        let pad: CGFloat = 28
        x = min(max(x, home.minX + pad), home.maxX - pad)
        y = min(max(y, home.minY + pad), home.maxY - pad)
    }

    func deflect(away normal: CGPoint, now: Double) {
        guard act != .chat, speed > 0 else { return }
        let inward = vx * normal.x + vy * normal.y
        guard inward < 0 else { return }
        var slide = CGPoint(x: vx - normal.x * inward, y: vy - normal.y * inward)
        if hypot(slide.x, slide.y) < 1 {
            slide = CGPoint(x: -normal.y * speed, y: normal.x * speed)
        }
        heading = atan2(slide.y, slide.x)
        targetHeading = heading
        speed = min(speed, hypot(slide.x, slide.y))
        targetSpeed = speed
        steerUntil = now + 0.6
        if act == .edge {
            act = .walk
            actUntil = now + 0.6
        }
    }

    private func pickAct(now: CFTimeInterval) {
        let roll = CGFloat.random(in: 0...1)
        if roll < 0.28 {
            act = .sit
            actUntil = now + CGFloat.random(in: 1.2...3.4)
        } else if roll < 0.46 {
            act = .stand
            actUntil = now + CGFloat.random(in: 0.6...1.8)
        } else if roll < 0.62 + 0.18 * memory.maturity() {
            act = .edge
            edge = nearestEdge()
            actUntil = now + CGFloat.random(in: 2.5...5.5)
            targetSpeed = CGFloat.random(in: 24...40)
        } else {
            act = .walk
            actUntil = now + CGFloat.random(in: 1.8...4.5)
            targetSpeed = CGFloat.random(in: 28...58)
        }
        targetSpeed *= 1 - 0.25 * memory.maturity()
    }

    private func nearestEdge() -> Int {
        let vf = home.insetBy(dx: 28, dy: 28)
        let distances = [y - vf.minY, vf.maxX - x, vf.maxY - y, x - vf.minX]
        return distances.indices.min { distances[$0] < distances[$1] } ?? 0
    }

    private func crawlEdge() {
        let vf = home.insetBy(dx: 28, dy: 28)
        let v = max(18, targetSpeed)
        let tolerance: CGFloat = 0.001
        let distance = [y - vf.minY, vf.maxX - x, vf.maxY - y, x - vf.minX][edge]
        if distance > tolerance {
            // Approach the boundary through the regular movement step; never teleport.
            let approach: [CGFloat] = [-.pi / 2, 0, .pi / 2, .pi]
            heading = approach[edge]
        } else {
            memory.visitEdge(edge)
            switch edge {
            case 0 where x >= vf.maxX - tolerance: edge = 1
            case 1 where y >= vf.maxY - tolerance: edge = 2
            case 2 where x <= vf.minX + tolerance: edge = 3
            case 3 where y <= vf.minY + tolerance: edge = 0
            default: break
            }
            let tangent: [CGFloat] = [0, .pi / 2, .pi, -.pi / 2]
            heading = tangent[edge]
        }
        // Separation must not push an edge walker away from its boundary each frame.
        sepX = 0
        sepY = 0
        targetHeading = heading
        targetSpeed = v
        speed = v
    }

    private func bounce() {
        let pad: CGFloat = 28
        let minX = home.minX + pad
        let maxX = home.maxX - pad
        let minY = home.minY + pad
        let maxY = home.maxY - pad
        if x < minX { x = minX; heading = atan2(sin(heading), abs(cos(heading))) }
        if x > maxX { x = maxX; heading = atan2(sin(heading), -abs(cos(heading))) }
        if y < minY { y = minY; heading = atan2(abs(sin(heading)), cos(heading)) }
        if y > maxY { y = maxY; heading = atan2(-abs(sin(heading)), cos(heading)) }
    }
}

private func lerpAngle(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
    var d = b - a
    while d > .pi { d -= 2 * .pi }
    while d < -.pi { d += 2 * .pi }
    return a + d * min(1, max(0, t))
}


@MainActor
private final class Bubble {
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

import AppKit
import QuartzCore

@MainActor
final class Critters: NSObject {
    static let shared = Critters()

    static let crawlKey = "critter.crawl"
    static let countKey = "critter.count"
    static let countChoices = [4, 8, 12, 16]
    static let rosterSize = ChargeLaw.roster

    var crawlOn: Bool {
        get { UserDefaults.standard.object(forKey: Self.crawlKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.crawlKey); apply() }
    }

    var count: Int {
        get {
            let n = UserDefaults.standard.object(forKey: Self.countKey) as? Int ?? 8
            return min(16, max(4, n))
        }
        set {
            UserDefaults.standard.set(min(16, max(4, newValue)), forKey: Self.countKey)
            trimYardToCap()
        }
    }

    var nestAnchor: CGPoint = .zero
    private(set) var colonists: [Colonist] = []
    private var bots: [Bot] { colonists.compactMap(\.bot) }
    private var swarms: [SwarmLayer] = []
    private var bubbles: [Bubble] = []
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var lastTick = CACurrentMediaTime()
    private var lastMouse = NSEvent.mouseLocation
    private var mouseWasNear = false
    private var lingerApp = ""
    private var lingerSince = CACurrentMediaTime()
    private var nextLinger = CACurrentMediaTime() + 40
    private var nextIdle = CACurrentMediaTime() + 50
    private var nextSave = CACurrentMediaTime() + 15
    private var nextPing = CACurrentMediaTime() + 5
    private var pendingReleaseID: Int?

    func start() {
        guard observers.isEmpty else { return }
        let nc = NotificationCenter.default
        observers = [
            nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.resetCrawlers() }
            },
        ]
        apply()
        if colonists.isEmpty { bootColony() }
        if crawlOn {
            ensureOverlays()
            fillYard()
        }
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
        ChargeStore.save(colonists)
        clearCrawlers()
        clearBubbles()
    }

    func apply() {
        if crawlOn {
            ensureOverlays()
            fillYard()
        } else {
            recallAll()
            clearBubbles()
        }
    }

    var yardCount: Int { colonists.filter { $0.post == .yard || $0.post == .emerging }.count }
    var homingCount: Int { colonists.filter { $0.post == .homing }.count }
    var warehouseCount: Int { colonists.filter { $0.post == .warehouse }.count }
    var chargingCount: Int { colonists.filter { $0.post == .warehouse && $0.charge < 1 }.count }

    var summaryLine: String {
        Copy.ui.summary(on: yardCount, cap: count, nest: warehouseCount)
    }

    func roster() -> [YardRow] {
        colonists.map {
            YardRow(id: $0.id, name: $0.name, code: $0.mbti.code, stage: $0.memory.stage().title,
                    charge: $0.charge, post: $0.post, refused: $0.memory.refused,
                    bodySize: $0.memory.bodySize(), worldVisible: crawlOn)
        }
    }

    func ping(_ id: Int, now: CFTimeInterval = CACurrentMediaTime()) {
        guard let colonist = colonists.first(where: { $0.id == id }) else { return }
        colonist.highlightUntil = now + 2.4
    }

    func toggle(_ id: Int) {
        guard let colonist = colonists.first(where: { $0.id == id }) else { return }
        ping(id)
        switch colonist.post {
        case .yard, .emerging:
            sendHome(colonist)
        case .homing:
            if colonist.charge >= ChargeLaw.talkBelow, deskRoom() > 0 {
                colonist.post = .yard
                colonist.bot?.aim = nil
                colonist.bot?.homebound = false
            }
        case .warehouse:
            release(colonist)
        }
    }

    private func deskRoom() -> Int {
        count - colonists.filter { $0.post == .yard || $0.post == .emerging || $0.post == .homing }.count
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let elapsed = max(0, min(now - lastTick, 1))
        let dt = min(elapsed, 0.033)
        lastTick = now
        tickBots(now: now, dt: dt, lid: RobotMark.lid(at: now))
        tickBubbles(now: now)
        if now >= nextPing {
            nextPing = now + 60
            Task { @MainActor in await CritterTalk.shared.refreshStatus() }
        }
        if now >= nextSave {
            nextSave = now + 15
            RobotMemoryStore.shared.save()
            ChargeStore.save(colonists)
        }
    }

    private func tickBots(now: CFTimeInterval, dt: CGFloat, lid: CGFloat) {
        if colonists.isEmpty {
            bootColony()
            if crawlOn { fillYard() }
        }
        tickCharge(now: now, dt: dt)
        rotatePosts(now: now)
        let visible = bots
        guard crawlOn || !visible.isEmpty else { return }
        ensureOverlays()
        scareFromMouse(now: now)
        meet(now: now)
        maybeLinger(now: now)
        maybeIdle(now: now)
        shareCharge(dt: dt)
        let contacts = BotPhysics.advance(visible, now: now, dt: dt)
        collide(contacts, now: now)
        for swarm in swarms {
            let box = swarm.panel.frame
            swarm.canvas.lid = lid
            swarm.canvas.highlights = Set(colonists.filter { $0.highlightUntil > now }.map(\.id))
            swarm.canvas.bots = visible.filter { $0.screenIndex == swarm.index }
            for bot in swarm.canvas.bots {
                bot.home = box
                if bot.aim == nil { bot.clampHome() }
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
        let active = yardBots()
        for c in active {
            let d = hypot(c.x - mouse.x, c.y - mouse.y)
            if d < nearestD {
                nearestD = d
                nearest = c
            }
            if d < 36 {
                closeCount += 1
                if let colonist = owner(c) {
                    colonist.charge = ChargeLaw.clamp(colonist.charge - ChargeLaw.scareCost)
                }
                c.aim = nil
                c.flee(from: mouse, now: now, boost: 1)
            }
        }
        let near = closeCount > 0
        if near, !mouseWasNear {
            for c in active {
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
        guard now >= nextLinger, now - lingerSince > 42,
              let c = yardBots().randomElement(), !app.isEmpty else { return }
        nextLinger = now + CGFloat.random(in: 50...80)
        say(.linger, bot: c, other: nil, scene: app)
    }

    private func maybeIdle(now: CFTimeInterval) {
        guard now >= nextIdle, !mouseWasNear,
              let c = yardBots().filter({ !$0.memory.refused && ChargeLaw.canTalk(owner($0)?.charge ?? 0) }).randomElement() else { return }
        nextIdle = now + CGFloat.random(in: 55...95)
        say(c.memory.stage() == .newborn ? .idle : .reflect, bot: c, other: nil)
    }

    private func say(_ event: CritterTalk.Event, bot: Bot, other: Bot?, scene: String? = nil, replyTo: String? = nil) {
        Task { @MainActor in
            _ = await utter(event, bot: bot, other: other, scene: scene, replyTo: replyTo)
        }
    }

    @discardableResult
    private func utter(_ event: CritterTalk.Event, bot: Bot, other: Bot?, scene: String? = nil, replyTo: String? = nil) async -> String? {
        guard !bot.memory.refused else { return nil }
        if event != .flee, !ChargeLaw.canTalk(owner(bot)?.charge ?? 0) { return nil }
        if event != .flee, owner(bot)?.post != .yard { return nil }
        let vibe = bot.mbti.vibe
        let otherVibe = other.map(\.mbti.vibe)
        let urgent = event == .flee || event == .chat || event == .scold
        let app = scene ?? WindowOwner.at(bot.point)
        if event == .linger || event == .idle, let app, !app.isEmpty {
            bot.memory.remember(.place, subject: app, detail: Copy.ui.linger(at: app))
        }
        let memory = bot.memory.context(kind: event.memoryKind, subject: other.map { String($0.id) })
        guard crawlOn, bots.contains(where: { $0 === bot }) else { return nil }
        guard let line = await CritterTalk.shared.speak(event: event, vibe: vibe, other: otherVibe, app: app, urgent: urgent, memory: memory, replyTo: replyTo) else {
            return nil
        }
        if event == .reflect { bot.memory.reflect(line) }
        else { bot.memory.remember(.speech, subject: "self", detail: line) }
        if let other, bots.contains(where: { $0 === other }) {
            other.memory.remember(.speech, subject: "\(bot.id)", detail: line)
        }
        bot.lastSpoken = line
        owner(bot)?.charge = ChargeLaw.clamp((owner(bot)?.charge ?? 0) - ChargeLaw.talkCost)
        popBubble(text: line, now: CACurrentMediaTime(), bot: bot)
        return line
    }

    private func converse(_ a: Bot, _ b: Bot, now: CFTimeInterval) {
        let pal = a.mbti.fits(b.mbti)
        let rounds = max(a.memory.chatRounds(with: b.id, pal: pal),
                         b.memory.chatRounds(with: a.id, pal: pal))
        a.memory.meet(b.id, friendly: true)
        b.memory.meet(a.id, friendly: true)
        let span = CGFloat(rounds) * 14
        Bot.pairTalk(a, b, now: now, secs: span...(span + 4))
        Task { @MainActor in
            var last: String?
            for _ in 0..<rounds {
                guard crawlOn, bots.contains(where: { $0 === a }), bots.contains(where: { $0 === b }),
                      CACurrentMediaTime() < a.chatUntil else { return }
                last = await utter(.chat, bot: a, other: b, replyTo: last)
                guard crawlOn, bots.contains(where: { $0 === a }), bots.contains(where: { $0 === b }),
                      CACurrentMediaTime() < a.chatUntil else { return }
                last = await utter(.chat, bot: b, other: a, replyTo: last)
            }
        }
    }

    private func meet(now: CFTimeInterval) {
        guard bots.count >= 2 else { return }
        for i in 0..<(bots.count - 1) {
            for j in (i + 1)..<bots.count {
                let a = bots[i]
                let b = bots[j]
                guard a.screenIndex == b.screenIndex else { continue }
                guard owner(a)?.post == .yard, owner(b)?.post == .yard else { continue }
                let d = hypot(a.x - b.x, a.y - b.y)
                let contactDistance = a.collisionRadius + b.collisionRadius
                guard d >= contactDistance - 0.001, d < contactDistance + 12,
                      a.canSocial(now: now), b.canSocial(now: now) else { continue }
                converse(a, b, now: now)
            }
        }
    }

    private func collide(_ contacts: [BotPhysics.Contact], now: CFTimeInterval) {
        for contact in contacts {
            let a = contact.a
            let b = contact.b
            guard owner(a)?.post == .yard, owner(b)?.post == .yard else { continue }
            a.memory.meet(b.id, friendly: false)
            b.memory.meet(a.id, friendly: false)
            owner(a)?.charge = ChargeLaw.clamp((owner(a)?.charge ?? 0) - ChargeLaw.bumpCost)
            owner(b)?.charge = ChargeLaw.clamp((owner(b)?.charge ?? 0) - ChargeLaw.bumpCost)
            guard a.canSocial(now: now), b.canSocial(now: now) else { continue }
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

    private func spawnSwarm() {
        bootColony()
        ensureOverlays()
        if crawlOn { fillYard() }
        RobotMemoryStore.shared.save()
    }

    private func bootColony() {
        guard colonists.isEmpty else { return }
        let saved = ChargeStore.load()
        colonists = (1...ChargeLaw.roster).map { id in
            let memory = RobotMemoryStore.shared.profile(id: id)
            return Colonist(id: id, memory: memory, charge: saved[id] ?? ChargeStore.seed(id: id))
        }
    }

    private func ensureOverlays() {
        guard swarms.isEmpty, !NSScreen.screens.isEmpty else { return }
        for (si, screen) in NSScreen.screens.enumerated() {
            let box = screen.visibleFrame
            let canvas = SwarmCanvas(frame: NSRect(origin: .zero, size: box.size))
            canvas.clipsToBounds = false
            canvas.index = si
            let panel = makeOverlay(size: box.size, level: .floating)
            canvas.autoresizingMask = [.width, .height]
            panel.contentView = canvas
            panel.setFrame(box, display: true)
            panel.orderFrontRegardless()
            swarms.append(SwarmLayer(panel: panel, canvas: canvas, home: panel.frame, index: si))
        }
    }

    private func fillYard() {
        var room = count - colonists.filter { $0.post == .yard || $0.post == .emerging || $0.post == .homing }.count
        let ranked = colonists.filter { $0.post == .warehouse }.sorted { $0.charge > $1.charge }
        for colonist in ranked where room > 0 && colonist.charge >= ChargeLaw.talkBelow {
            appear(colonist, post: .emerging, fromNest: true)
            room -= 1
        }
    }

    private func trimYardToCap() {
        let extra = colonists.filter { $0.post == .yard || $0.post == .emerging }
            .sorted { $0.charge < $1.charge }
        let overflow = max(0, extra.count - count)
        for colonist in extra.prefix(overflow) { sendHome(colonist) }
    }

    private func recallAll() {
        pendingReleaseID = nil
        for colonist in colonists where colonist.post.onDesk { despawn(colonist) }
        clearCrawlers()
    }

    private func sendHome(_ colonist: Colonist) {
        colonist.post = .homing
        if colonist.bot == nil { appear(colonist, post: .homing, fromNest: false) }
        guard let bot = colonist.bot else { return }
        bot.headHome(to: nest(for: bot))
    }

    private func release(_ colonist: Colonist) {
        guard crawlOn else { return }
        guard colonist.charge >= ChargeLaw.talkBelow else { return }
        let occupying = colonists.filter { $0.post == .yard || $0.post == .emerging || $0.post == .homing }.count
        if occupying >= count {
            pendingReleaseID = colonist.id
            if let tired = ChargeLaw.pickSwap(onYard: colonists.filter { $0.post == .yard }.map { ($0.id, $0.charge) }),
               let other = colonists.first(where: { $0.id == tired }), other.id != colonist.id {
                sendHome(other)
            }
            return
        }
        if pendingReleaseID == colonist.id { pendingReleaseID = nil }
        if colonist.bot == nil { appear(colonist, post: .emerging, fromNest: true) }
        colonist.post = .emerging
        colonist.bot?.aim = emergeTarget(for: colonist.bot)
    }

    private func appear(_ colonist: Colonist, post: ChargeLaw.Post, fromNest: Bool) {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        let si = nestScreenIndex()
        let box = swarms.first { $0.index == si }?.panel.frame ?? screens[min(si, screens.count - 1)].visibleFrame
        let bot = Bot(id: colonist.id, mbti: colonist.mbti, home: box, screenIndex: si, memory: colonist.memory)
        if fromNest {
            let nest = nestPoint(in: box)
            bot.x = nest.x + CGFloat((colonist.id % 5) - 2) * 16
            bot.y = nest.y
            bot.aim = emergeTarget(for: bot)
        }
        bot.energy = colonist.charge
        colonist.bot = bot
        colonist.post = post
    }

    private func despawn(_ colonist: Colonist) {
        colonist.bot = nil
        colonist.post = .warehouse
    }

    private func tickCharge(now: CFTimeInterval, dt: Double) {
        for colonist in colonists {
            switch colonist.post {
            case .warehouse:
                colonist.charge = ChargeLaw.fill(colonist.charge, dt: dt)
            case .yard, .homing, .emerging:
                let bot = colonist.bot
                colonist.charge = ChargeLaw.drain(colonist.charge, dt: dt,
                                                  speed: Double(bot?.speed ?? 0),
                                                  fleeing: bot?.act == .flee,
                                                  sitting: bot?.act == .sit || bot?.act == .chat || bot?.act == .stand,
                                                  refused: colonist.memory.refused,
                                                  post: colonist.post)
            }
            colonist.bot?.energy = colonist.charge
            colonist.bot?.limp = 1
        }
    }

    private func rotatePosts(now: CFTimeInterval) {
        for colonist in colonists {
            if ChargeLaw.shouldGoHome(colonist.charge, post: colonist.post) {
                sendHome(colonist)
            }
        }
        swallowHomers()
        finishEmerging()
        if crawlOn {
            if deskRoom() > 0,
               let id = pendingReleaseID,
               let pending = colonists.first(where: { $0.id == id && $0.post == .warehouse }) {
                release(pending)
            }
            var released = 0
            while released < ChargeLaw.roster {
                let warehouse = colonists.filter { $0.post == .warehouse }.map { ($0.id, $0.charge) }
                let onYard = colonists.filter { $0.post == .yard || $0.post == .emerging || $0.post == .homing }.count
                guard let id = ChargeLaw.pickRelease(from: warehouse, cap: count, onYard: onYard),
                      let colonist = colonists.first(where: { $0.id == id && $0.post == .warehouse })
                else { break }
                let before = colonist.post
                release(colonist)
                guard colonist.post != before else { break }
                released += 1
            }
        }
        _ = now
    }

    private func swallowHomers() {
        let nest = nestPoint(in: homeForNest())
        for colonist in colonists where colonist.post == .homing {
            guard let bot = colonist.bot else {
                despawn(colonist)
                continue
            }
            bot.aim = nest
            if hypot(bot.x - nest.x, bot.y - nest.y) < 26 {
                despawn(colonist)
            }
        }
    }

    private func finishEmerging() {
        for colonist in colonists where colonist.post == .emerging {
            guard let bot = colonist.bot else {
                colonist.post = .yard
                continue
            }
            if bot.aim == nil { bot.aim = emergeTarget(for: bot) }
            if let aim = bot.aim, hypot(bot.x - aim.x, bot.y - aim.y) < 36 {
                colonist.post = .yard
                bot.aim = nil
            }
        }
    }

    private func shareCharge(dt: Double) {
        let yard = colonists.filter { $0.post == .yard && $0.bot != nil }
        for i in 0..<yard.count {
            for j in (i + 1)..<yard.count {
                let a = yard[i]
                let b = yard[j]
                guard let pa = a.bot, let pb = b.bot, pa.screenIndex == pb.screenIndex else { continue }
                guard hypot(pa.x - pb.x, pa.y - pb.y) < ChargeLaw.shareRadius else { continue }
                if a.charge >= b.charge {
                    let next = ChargeLaw.share(rich: a.charge, poor: b.charge, dt: dt)
                    a.charge = next.0; b.charge = next.1
                } else {
                    let next = ChargeLaw.share(rich: b.charge, poor: a.charge, dt: dt)
                    b.charge = next.0; a.charge = next.1
                }
            }
        }
    }

    private func owner(_ bot: Bot) -> Colonist? { colonists.first { $0.bot === bot } }

    private func yardBots() -> [Bot] {
        colonists.filter { $0.post == .yard }.compactMap(\.bot)
    }

    private func nestScreenIndex() -> Int {
        guard nestAnchor != .zero else { return 0 }
        return NSScreen.screens.firstIndex { $0.frame.contains(nestAnchor) } ?? 0
    }

    private func homeForNest() -> NSRect {
        let screens = NSScreen.screens
        let si = nestScreenIndex()
        if let swarm = swarms.first(where: { $0.index == si }) { return swarm.panel.frame }
        guard !screens.isEmpty else { return NSRect(x: 0, y: 0, width: 800, height: 600) }
        return screens[min(si, screens.count - 1)].visibleFrame
    }

    private func nestPoint(in box: NSRect) -> CGPoint {
        let x = nestAnchor == .zero ? box.midX : min(max(nestAnchor.x, box.minX + 40), box.maxX - 40)
        return CGPoint(x: x, y: box.maxY - 30)
    }

    private func nest(for bot: Bot?) -> CGPoint {
        nestPoint(in: bot?.home ?? homeForNest())
    }

    private func emergeTarget(for bot: Bot?) -> CGPoint {
        let box = bot?.home ?? homeForNest()
        let nest = nestPoint(in: box)
        return CGPoint(x: nest.x + CGFloat.random(in: -80...80), y: box.midY + CGFloat.random(in: -40...80))
    }

    private func resetCrawlers() {
        ChargeStore.save(colonists)
        RobotMemoryStore.shared.save()
        clearBubbles()
        for swarm in swarms { swarm.panel.orderOut(nil) }
        swarms = []
        for colonist in colonists { colonist.bot = nil }
        if crawlOn {
            ensureOverlays()
            for colonist in colonists where colonist.post.onDesk && colonist.post != .warehouse {
                appear(colonist, post: colonist.post, fromNest: colonist.post != .yard)
            }
        }
    }

    private func clearCrawlers() {
        for swarm in swarms { swarm.panel.orderOut(nil) }
        swarms = []
        for colonist in colonists { colonist.bot = nil }
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
            RobotMark.drawBot(in: g, lid: lid, gait: bot.gait, speed: bot.speed, sit: bot.sit,
                              tired: 1 - bot.limp, glow: highlights.contains(bot.id))
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
    var lastSpoken: String?
    var aim: CGPoint?
    var energy: Double = 1
    var limp: Double = 1
    var homebound = false
    private var sepX: CGFloat = 0
    private var sepY: CGFloat = 0
    private let wander: CGFloat
    private let gaitScale: CGFloat
    var bodySize: CGFloat { memory.bodySize() }
    var collisionRadius: CGFloat { bodySize * 0.6 + 1.5 }

    var vx: CGFloat { cos(heading) * speed }
    var vy: CGFloat { sin(heading) * speed }
    var planted: Bool { act == .sit || act == .stand || act == .chat }
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
        now > panicUntil && now > chatUntil && now > chatCool && act != .flee && aim == nil
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
            memory.remember(.mouse, detail: Copy.ui.flee)
        }
        pal = nil
        chatUntil = 0
        aim = nil
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

    func headHome(to target: CGPoint) {
        homebound = true
        pal = nil
        chatUntil = 0
        chatCool = 0
        panicUntil = 0
        bumpUntil = 0
        act = .walk
        aim = target
        heading = atan2(target.y - y, target.x - x)
        targetHeading = heading
        speed = max(speed, 24)
        targetSpeed = 38
        sit = 0
    }

    func separate(from others: [Bot]) {
        sepX = 0
        sepY = 0
        guard act != .chat, act != .sit, act != .stand, aim == nil else { return }
        var n: CGFloat = 0
        for o in others {
            if o === self || o.screenIndex != screenIndex { continue }
            let dx = x - o.x
            let dy = y - o.y
            let d = hypot(dx, dy)
            let personalSpace = collisionRadius + o.collisionRadius + spacing(to: o)
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

    private func spacing(to other: Bot) -> CGFloat { 10 }

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
        } else if let aim {
            let dx = aim.x - x
            let dy = aim.y - y
            let d = hypot(dx, dy)
            if d < 8 {
                speed = 0
                targetSpeed = 0
                act = .sit
            } else {
                act = .walk
                targetHeading = atan2(dy, dx)
                heading = lerpAngle(heading, targetHeading, 1 - exp(-dt * 4.2))
                targetSpeed = 38 * limp
                speed += (targetSpeed - speed) * (1 - exp(-dt * 3))
            }
        } else {
            if now > actUntil { pickAct(now: now) }
            switch act {
            case .sit, .stand, .chat:
                targetSpeed = 0
                speed = 0
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
        if planted {
            speed = 0
            targetSpeed = 0
            sepX = 0
            sepY = 0
        } else {
            if hypot(sepX, sepY) > 0.08 {
                targetHeading = lerpAngle(targetHeading, atan2(sepY, sepX), 0.22)
            }
            x += cos(heading) * speed * dt
            y += sin(heading) * speed * dt
            if speed > 8 { traveled += speed * dt }
            if aim == nil { bounce() }
        }
        if aim == nil { clampHome() }
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
        guard act != .chat, !planted, speed > 8, aim == nil else { return }
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

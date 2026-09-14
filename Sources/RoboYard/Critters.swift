import AppKit
import QuartzCore

@MainActor
final class Critters: NSObject {
    static let shared = Critters()

    static let crawlKey = "critter.crawl"
    static let countKey = "critter.count"
    static let powerKey = "critter.powersaver"
    nonisolated static let countChoices = [4, 8, 12, 16, 24]
    static let rosterSize = ChargeLaw.roster

    var powerSaver: Bool {
        get { UserDefaults.standard.object(forKey: Self.powerKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: Self.powerKey); restartTimer() }
    }

    var petClick: Bool {
        get { UserDefaults.standard.object(forKey: PetLaw.clickKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: PetLaw.clickKey) }
    }

    var quietNights: Bool {
        get { UserDefaults.standard.object(forKey: Rhythm.quietKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Rhythm.quietKey) }
    }

    private(set) var screenAsleep = false

    var bubbleCap: Int { powerSaver ? 4 : 8 }

    var crawlOn: Bool {
        get { UserDefaults.standard.object(forKey: Self.crawlKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.crawlKey); apply() }
    }

    var count: Int {
        get {
            let n = UserDefaults.standard.object(forKey: Self.countKey) as? Int ?? 8
            return min(24, max(4, n))
        }
        set {
            UserDefaults.standard.set(min(24, max(4, newValue)), forKey: Self.countKey)
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
    private var mouseSpeed: CGFloat = 0
    private var mouseWasNear = false
    private var lingerApp = ""
    private var lingerSince = CACurrentMediaTime()
    private var nextLinger = CACurrentMediaTime() + 40
    private var nextIdle = CACurrentMediaTime() + 50
    private var nextSave = CACurrentMediaTime() + 15
    private var nextPing = CACurrentMediaTime() + 5
    private var pendingReleaseID: Int?
    private var frame = 0
    private var clickMonitor: Any?
    private var lastFeed: CFTimeInterval = 0
    private var sleepObservers: [NSObjectProtocol] = []

    func restartTimer() {
        timer?.invalidate()
        let interval = powerSaver ? 1.0 / 30.0 : 1.0 / 60.0
        let t = Timer(timeInterval: interval, target: self, selector: #selector(objcTick), userInfo: nil, repeats: true)
        t.tolerance = 0.004
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func start() {
        guard observers.isEmpty else { return }
        let nc = NotificationCenter.default
        observers = [
            nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.resetCrawlers() }
            },
        ]
        let wc = NSWorkspace.shared.notificationCenter
        sleepObservers = [
            wc.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.screenAsleep = true }
            },
            wc.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.screenAsleep = false }
            },
        ]
        apply()
        if colonists.isEmpty { bootColony() }
        if crawlOn {
            ensureOverlays()
            fillYard()
        }
        let timer = Timer(timeInterval: powerSaver ? 1.0 / 30.0 : 1.0 / 60.0, target: self, selector: #selector(objcTick), userInfo: nil, repeats: true)
        timer.tolerance = 0.004
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        watchClicks()
    }

    @objc private func objcTick() {
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
        sleepObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        sleepObservers = []
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
        colonists.map { c in
            let friend = c.memory.closestFriend()
            var badges: [String] = []
            if let friend {
                let level = friend.meetings >= 12 ? 3 : friend.meetings >= 6 ? 2 : friend.meetings >= 3 ? 1 : 0
                if level > 0 { badges.append(Copy.ui.bondBadge(level) + " · \(friend.id)号") }
            }
            if c.memory.hasBoundaryMilestone() { badges.append(Copy.ui.milestoneBadge) }
            let badge: String? = badges.isEmpty ? nil : badges.joined(separator: " · ")
            return YardRow(id: c.id, name: c.name, code: c.mbti.code, stage: c.memory.stage().title,
                           charge: c.charge, post: c.post, refused: c.memory.refused,
                           bodySize: c.memory.bodySize(), worldVisible: crawlOn, friendBadge: badge,
                           group: c.mbti.group, stageLevel: c.memory.stage().rawValue)
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

    // MARK: - 2.0 interaction: pet, feed, rename

    private func watchClicks() {
        guard clickMonitor == nil else { return }
        // Global monitor observes without swallowing: the desktop stays clickable.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            Task { @MainActor in self?.handleClickPet() }
        }
    }

    private func handleClickPet() {
        guard petClick, crawlOn, !NSApp.isActive else { return }
        let point = NSEvent.mouseLocation
        let now = CACurrentMediaTime()
        let candidates = scareBots().map { (id: $0.id, point: $0.point) }
        guard let id = PetLaw.target(at: point, among: candidates),
              let colonist = colonists.first(where: { $0.id == id }),
              let bot = colonist.bot,
              PetLaw.canPet(lastPet: bot.petCool, now: now)
        else { return }
        // Same display-level turn-taking as model lines (fixes #1):
        // wait for visible bubbles to expire, then re-validate so rapid
        // double-clicks can't double-apply.
        Task { @MainActor [weak self, weak bot, weak colonist] in
            guard let self, let bot, let colonist else { return }
            await self.waitForBubbleTurn(bot: bot, other: nil, timeout: 3)
            let later = CACurrentMediaTime()
            guard self.crawlOn,
                  colonist.post == .yard || colonist.post == .emerging,
                  self.bots.contains(where: { $0 === bot }),
                  PetLaw.canPet(lastPet: bot.petCool, now: later)
            else { return }
            self.pet(colonist, bot: bot, now: later)
        }
    }

    private func pet(_ colonist: Colonist, bot: Bot, now: CFTimeInterval) {
        bot.petCool = now + PetLaw.cooldown
        // The click catches it: stop fleeing and stay calm briefly so the
        // still-parked pointer doesn't re-scare it next tick (fixes #4).
        bot.panicUntil = 0
        bot.calmUntil = now + ScareLaw.calmAfterPet
        colonist.charge = ChargeLaw.clamp(colonist.charge + PetLaw.chargeGain)
        let line = Copy.ui.petLine(colonist.id)
        colonist.memory.remember(.care, subject: "petted", detail: Copy.ui.petted(colonist.name))
        colonist.memory.remember(.speech, subject: "self", detail: line)
        colonist.highlightUntil = now + 1.2
        popBubble(text: line, now: now, bot: bot)
    }

    /// Seconds until feeding is available again. 0 means ready now.
    func feedCooldownLeft(now: CFTimeInterval = CACurrentMediaTime()) -> Int {
        max(0, Int(ceil(lastFeed + PetLaw.feedCooldown - now)))
    }

    @discardableResult
    func feedDesk(now: CFTimeInterval = CACurrentMediaTime()) -> Bool {
        guard PetLaw.canFeed(lastFeed: lastFeed, now: now) else { return false }
        let diners = colonists.filter { $0.post == .yard }
        guard !diners.isEmpty else { return false }
        lastFeed = now
        for colonist in diners {
            colonist.charge = ChargeLaw.clamp(colonist.charge + PetLaw.feedGain)
            colonist.memory.remember(.care, subject: "fed", detail: Copy.ui.fed(colonist.name), now: Date())
            colonist.highlightUntil = now + 1.2
        }
        return true
    }

    func rename(_ id: Int, to raw: String) {
        guard let colonist = colonists.first(where: { $0.id == id }) else { return }
        let clean = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(12))
        colonist.memory.nickname = clean.isEmpty ? nil : clean
        if !clean.isEmpty {
            colonist.memory.remember(.care, subject: "renamed", detail: Copy.ui.renamed(clean))
        }
        ping(id)
        RobotMemoryStore.shared.save()
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
        scareFromMouse(now: now, dt: dt)
        meet(now: now)
        maybeLinger(now: now)
        maybeIdle(now: now)
        shareCharge(now: now, dt: dt)
        let contacts = BotPhysics.advance(visible, now: now, dt: dt)
        collide(contacts, now: now)
        frame += 1
        let milestoneIDs = Set(colonists.filter { $0.memory.hasBoundaryMilestone() }.map(\.id))
        for swarm in swarms {
            let box = swarm.panel.frame
            swarm.canvas.lid = lid
            var glow = Set(colonists.filter { $0.highlightUntil > now }.map(\.id))
            glow.formUnion(milestoneIDs)
            swarm.canvas.highlights = glow
            swarm.canvas.bots = visible.filter { $0.screenIndex == swarm.index }
            for bot in swarm.canvas.bots {
                bot.home = box
                if bot.aim == nil { bot.clampHome() }
            }
            if powerSaver {
                // Saver: redraw every frame only when something moves;
                // planted crowds refresh at ~10fps for blinking.
                let moving = swarm.canvas.bots.contains { !$0.planted || $0.speed > 1 }
                if !moving, frame % 3 != 0 { continue }
            }
            swarm.canvas.needsDisplay = true
        }
    }

    private func scareBots() -> [Bot] {
        colonists.filter { Self.canScare(post: $0.post) }.compactMap(\.bot)
    }

    private func scareFromMouse(now: CFTimeInterval, dt: CGFloat) {
        let mouse = NSEvent.mouseLocation
        if dt > 0.000_001 {
            let instant = hypot(mouse.x - lastMouse.x, mouse.y - lastMouse.y) / dt
            mouseSpeed += (min(instant, 4000) - mouseSpeed) * 0.35
        }
        lastMouse = mouse
        var nearest: Bot?
        var nearestD: CGFloat = .greatestFiniteMagnitude
        var closeCount = 0
        let active = scareBots()
        for c in active {
            let d = hypot(c.x - mouse.x, c.y - mouse.y)
            if d < nearestD {
                nearestD = d
                nearest = c
            }
            // A fresh pet grants brief calm; the touch band always scares,
            // the outer band only for fast pointer movement (fixes #4).
            guard now >= c.calmUntil,
                  ScareLaw.shouldScare(distance: d, speed: mouseSpeed)
            else { continue }
            closeCount += 1
            if now >= c.scareCool {
                c.scareCool = now + Self.scareCooldown
                if let colonist = owner(c) {
                    colonist.charge = ChargeLaw.clamp(colonist.charge - ChargeLaw.scareCost)
                }
            }
            c.aim = nil
            c.flee(from: mouse, now: now, boost: 1)
        }
        let near = closeCount > 0
        if near, !mouseWasNear {
            for c in active {
                guard now >= c.calmUntil else { continue }
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
        // Milestone bots reflect more often: shorter cooldown so the edge story surfaces.
        nextIdle = now + (c.memory.hasBoundaryMilestone() ? CGFloat.random(in: 30...50) : CGFloat.random(in: 55...95))
        say(c.memory.stage() == .newborn ? .idle : .reflect, bot: c, other: nil)
    }

    private func say(_ event: CritterTalk.Event, bot: Bot, other: Bot?, scene: String? = nil, replyTo: String? = nil, grudge: Int = 0) {
        Task { @MainActor in
            _ = await utter(event, bot: bot, other: other, scene: scene, replyTo: replyTo, grudge: grudge)
        }
    }

    /// Speech is muted at night and while the screen is locked; bodies keep moving.
    private func isSilent() -> Bool {
        if screenAsleep { return true }
        return quietNights && Rhythm.isQuiet()
    }

    @discardableResult
    private func utter(_ event: CritterTalk.Event, bot: Bot, other: Bot?, scene: String? = nil, replyTo: String? = nil, grudge: Int = 0) async -> String? {
        guard !bot.memory.refused else { return nil }
        if isSilent() { return nil }
        if event != .flee, !ChargeLaw.canTalk(owner(bot)?.charge ?? 0) { return nil }
        if event != .flee, owner(bot)?.post != .yard { return nil }
        let vibe = bot.mbti.vibe
        let otherVibe = other.map(\.mbti.vibe)
        let urgent = event == .flee || event == .chat || event == .scold
        let rawApp = scene ?? WindowOwner.at(bot.point)
        let app = CritterTalk.shared.shareAppName ? rawApp : nil
        let meetings = other.map { bot.memory.meetings(with: $0.id) } ?? 0
        let pal = other.map { bot.mbti.fits($0.mbti) } ?? false
        if event == .linger || event == .idle, let app, !app.isEmpty {
            bot.memory.remember(.place, subject: app, detail: Copy.ui.linger(at: app))
        }
        let memory = bot.memory.context(kind: event.memoryKind, subject: other.map { String($0.id) })
        guard crawlOn, bots.contains(where: { $0 === bot }) else { return nil }
        let milestone = event == .reflect && bot.memory.hasBoundaryMilestone()
        let reunion: (gap: TimeInterval, line: String?)? = if event == .chat, replyTo == nil,
            let peer = other, let gap = bot.memory.gap(with: peer.id) {
            (gap, bot.memory.reminiscence(about: peer.id))
        } else {
            nil
        }
        guard let line = await CritterTalk.shared.speak(event: event, vibe: vibe, other: otherVibe, app: app, urgent: urgent, memory: memory, replyTo: replyTo, meetings: meetings, pal: pal, milestone: milestone, grudge: grudge, reunion: reunion) else {
            return nil
        }
        if event != .flee {
            // Turn-taking at the display level: don't stack this bubble onto
            // a still-visible bubble of either participant. Bubbles expire on
            // their own, so waiting can't deadlock; the timeout only bounds
            // how long a queued line holds the conversation.
            await waitForBubbleTurn(bot: bot, other: other, timeout: 6)
            guard crawlOn, bots.contains(where: { $0 === bot }) else { return nil }
            if event != .flee, owner(bot)?.post != .yard { return nil }
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
                      a.pal === b, b.pal === a,
                      CACurrentMediaTime() < a.chatUntil else { return }
                last = await utter(.chat, bot: a, other: b, replyTo: last)
                guard crawlOn, bots.contains(where: { $0 === a }), bots.contains(where: { $0 === b }),
                      a.pal === b, b.pal === a,
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
            say(.scold, bot: a, other: b, grudge: a.memory.collisions(with: b.id))
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

    nonisolated static let bubbleDuration: CFTimeInterval = 2.3
    /// Per-bot cooldown for the scare charge cost, so chasing doesn't drain per frame.
    nonisolated static let scareCooldown: CFTimeInterval = 1.0

    /// Yard bots plus freshly released (emerging) ones can be scattered by the
    /// pointer. Homing bots are left alone so the trip back to the menu bar
    /// isn't fought frame by frame.
    nonisolated static func canScare(post: ChargeLaw.Post) -> Bool {
        post == .yard || post == .emerging
    }

    /// Seconds to wait before showing a bubble while `existingUntil` is still visible.
    nonisolated static func bubbleWaitSeconds(existingUntil: CFTimeInterval, now: CFTimeInterval) -> CFTimeInterval {
        max(0, existingUntil - now)
    }

    private func bubbleVisible(_ bot: Bot?, now: CFTimeInterval) -> Bool {
        guard let bot else { return false }
        return bubbles.contains { $0.bot === bot && now < $0.until }
    }

    private func waitForBubbleTurn(bot: Bot, other: Bot?, timeout: CFTimeInterval) async {
        let deadline = CACurrentMediaTime() + timeout
        while CACurrentMediaTime() < deadline {
            let now = CACurrentMediaTime()
            if !bubbleVisible(bot, now: now), !bubbleVisible(other, now: now) { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    @discardableResult
    private func popBubble(text: String, now: CFTimeInterval, bot: Bot?, at: CGPoint? = nil) -> Bubble {
        if bubbles.count >= bubbleCap {
            bubbles.removeFirst().kill()
        }
        let view = BubbleView(text: text)
        let size = view.fitting
        let panel = makeOverlay(size: size, level: .statusBar)
        view.frame = NSRect(origin: .zero, size: size)
        panel.contentView = view
        panel.setFrame(bubbleFrame(size: size, bot: bot, at: at), display: false)
        panel.orderFrontRegardless()
        let bubble = Bubble(panel: panel, view: view, until: now + Self.bubbleDuration, bot: bot)
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
            colonist.bot?.limp = ChargeLaw.limp(for: colonist.charge)
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

    private func shareCharge(now: CFTimeInterval, dt: Double) {
        let yard = colonists.filter { $0.post == .yard && $0.bot != nil }
        for i in 0..<yard.count {
            for j in (i + 1)..<yard.count {
                let a = yard[i]
                let b = yard[j]
                guard let pa = a.bot, let pb = b.bot, pa.screenIndex == pb.screenIndex else { continue }
                guard hypot(pa.x - pb.x, pa.y - pb.y) < ChargeLaw.shareRadius else { continue }
                let before = abs(a.charge - b.charge)
                if a.charge >= b.charge {
                    let next = ChargeLaw.share(rich: a.charge, poor: b.charge, dt: dt)
                    a.charge = next.0; b.charge = next.1
                } else {
                    let next = ChargeLaw.share(rich: b.charge, poor: a.charge, dt: dt)
                    b.charge = next.0; a.charge = next.1
                }
                // Visible feedback: a meaningful transfer briefly glows both bots.
                if before > 0.04, abs(a.charge - b.charge) < before {
                    a.highlightUntil = max(a.highlightUntil, now + 1.2)
                    b.highlightUntil = max(b.highlightUntil, now + 1.2)
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

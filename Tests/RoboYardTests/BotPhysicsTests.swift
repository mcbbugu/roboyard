import AppKit
import Testing
@testable import RoboYard

@MainActor
struct BotPhysicsTests {
    private let home = NSRect(x: 0, y: 0, width: 1000, height: 800)

    @Test
    func collisionVolumeWorksWhileTalkingAndDuringCooldown() {
        let a = makeBot(id: 1, x: 400)
        let b = makeBot(id: 2, x: 400)
        a.act = .chat
        b.act = .chat
        a.chatCool = 1000
        b.chatCool = 1000
        let contacts = BotPhysics.resolve([a, b], now: 1)
        #expect(contacts.count == 1)
        #expect(hypot(a.x - b.x, a.y - b.y) >= a.collisionRadius + b.collisionRadius - 0.002)
    }

    @Test
    func largerBodiesHaveLargerCollidersAndAreHarderToPush() {
        let small = makeBot(id: 1, x: 400)
        let large = makeBot(id: 2, x: 420, memory: grownMemory(id: 2))
        #expect(large.collisionRadius > small.collisionRadius)
        let beforeSmall = small.x
        let beforeLarge = large.x
        _ = BotPhysics.resolve([small, large], now: 1)
        #expect(beforeSmall - small.x > large.x - beforeLarge)
        #expect(large.x - small.x >= large.collisionRadius + small.collisionRadius - 0.002)
    }

    @Test
    func fleeingBotsDoNotPassThroughEachOther() {
        let a = makeBot(id: 1, x: 470)
        let b = makeBot(id: 2, x: 530)
        a.heading = 0
        b.heading = .pi
        for bot in [a, b] {
            bot.act = .flee
            bot.panicUntil = 1000
            bot.speed = 230
            bot.targetSpeed = 230
            bot.targetHeading = bot.heading
        }
        var touched = false
        for i in 0..<60 {
            let contacts = BotPhysics.advance([a, b], now: 1 + Double(i) / 30, dt: 1.0 / 30)
            touched = touched || !contacts.isEmpty
            #expect(hypot(a.x - b.x, a.y - b.y) >= a.collisionRadius + b.collisionRadius - 0.002)
        }
        #expect(touched)
    }

    @Test
    func wallContactAndCrowdingDoNotLeaveBodiesOverlapping() {
        let a = makeBot(id: 1, x: 28)
        let b = makeBot(id: 2, x: 35)
        let c = makeBot(id: 3, x: 42)
        let bots = [a, b, c]
        _ = BotPhysics.resolve(bots, now: 1)
        for i in 0..<bots.count {
            #expect(bots[i].x >= 28)
            for j in (i + 1)..<bots.count {
                #expect(hypot(bots[i].x - bots[j].x, bots[i].y - bots[j].y)
                        >= bots[i].collisionRadius + bots[j].collisionRadius - 0.01)
            }
        }
    }

    @Test
    func separateScreensDoNotCollide() {
        let a = makeBot(id: 1, x: 400)
        let b = Bot(id: 2, mbti: .intj, home: home, screenIndex: 1)
        b.x = a.x
        b.y = a.y
        #expect(BotPhysics.resolve([a, b], now: 1).isEmpty)
        #expect(a.point == b.point)
    }

    @Test
    func plantedBotsDoNotSlideFromCrowding() {
        let a = makeBot(id: 1, x: 400)
        let b = makeBot(id: 2, x: 430)
        a.act = .sit
        b.act = .sit
        a.actUntil = 1000
        b.actUntil = 1000
        let before = a.point
        for i in 0..<30 {
            _ = BotPhysics.advance([a, b], now: 1 + Double(i) / 60, dt: 1.0 / 60)
        }
        #expect(hypot(a.x - before.x, a.y - before.y) < 0.15)
        #expect(a.act == .sit)
    }

    @Test
    func overlappingSittersUnstickOnceThenStay() {
        let a = makeBot(id: 1, x: 400)
        let b = makeBot(id: 2, x: 408)
        a.act = .sit
        b.act = .sit
        a.actUntil = 1000
        b.actUntil = 1000
        _ = BotPhysics.resolve([a, b], now: 1)
        let stayA = a.point
        let stayB = b.point
        for i in 0..<45 {
            _ = BotPhysics.advance([a, b], now: 2 + Double(i) / 60, dt: 1.0 / 60)
        }
        #expect(hypot(a.x - stayA.x, a.y - stayA.y) < 0.2)
        #expect(hypot(b.x - stayB.x, b.y - stayB.y) < 0.2)
    }

    private func makeBot(id: Int, x: CGFloat, memory: RobotMemory? = nil) -> Bot {
        let bot = Bot(id: id, mbti: .intj, home: home, screenIndex: 0, memory: memory)
        bot.x = x
        bot.y = 400
        bot.speed = 0
        bot.targetSpeed = 0
        bot.actUntil = 1000
        return bot
    }
}

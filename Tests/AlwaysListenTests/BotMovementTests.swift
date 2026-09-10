import AppKit
import Testing
@testable import AlwaysListen

@MainActor
struct BotMovementTests {
    private let home = NSRect(x: -1000, y: 100, width: 1000, height: 800)
    private let dt: CGFloat = 1.0 / 60

    @Test(arguments: 0..<4)
    func approachesEdgeWithoutTeleporting(edge: Int) {
        let bot = makeBot(edge: edge)
        var reachedEdge = false
        let bounds = home.insetBy(dx: 28, dy: 28)
        for frame in 0..<1200 {
            let before = bot.point
            bot.step(now: Double(frame) * dt + 1, dt: dt)
            let displacement = hypot(bot.x - before.x, bot.y - before.y)
            #expect(displacement <= 30 * dt + 0.001)
            #expect(bot.x >= bounds.minX && bot.x <= bounds.maxX)
            #expect(bot.y >= bounds.minY && bot.y <= bounds.maxY)
            let distance = [bot.y - bounds.minY, bounds.maxX - bot.x,
                            bounds.maxY - bot.y, bot.x - bounds.minX][edge]
            if distance < 0.001 { reachedEdge = true }
        }
        #expect(reachedEdge)
    }

    @Test(arguments: 0..<4)
    func turnsAtCornerAndKeepsMoving(edge: Int) {
        let bot = makeBot(edge: edge)
        let bounds = home.insetBy(dx: 28, dy: 28)
        let starts: [CGPoint] = [
            CGPoint(x: bounds.maxX - 1, y: bounds.minY),
            CGPoint(x: bounds.maxX, y: bounds.maxY - 1),
            CGPoint(x: bounds.minX + 1, y: bounds.maxY),
            CGPoint(x: bounds.minX, y: bounds.minY + 1),
        ]
        bot.x = starts[edge].x
        bot.y = starts[edge].y
        for frame in 0..<180 {
            bot.step(now: Double(frame) * dt + 1, dt: dt)
        }
        #expect(bot.edge == (edge + 1) % 4)
        let progress = [bot.y - bounds.minY, bounds.maxX - bot.x,
                        bounds.maxY - bot.y, bot.x - bounds.minX][edge]
        #expect(progress > 60)
    }

    @Test
    func choosingNewActionsDoesNotRelocateBot() {
        let bot = makeBot(edge: 0)
        // Exercise actual action selection as well as the edge movement itself.
        for _ in 0..<512 {
            bot.x = home.midX
            bot.y = home.midY
            bot.actUntil = 0
            let before = bot.point
            bot.step(now: 1, dt: dt)
            #expect(hypot(bot.x - before.x, bot.y - before.y) <= 60 * dt + 0.001)
        }
    }

    private func makeBot(edge: Int) -> Bot {
        let bot = Bot(id: edge, mbti: .intj, home: home, screenIndex: 0)
        bot.x = home.midX
        bot.y = home.midY
        bot.act = .edge
        bot.edge = edge
        bot.actUntil = 1000
        bot.targetSpeed = 30
        return bot
    }
}

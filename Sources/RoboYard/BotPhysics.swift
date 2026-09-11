import AppKit

@MainActor
enum BotPhysics {
    struct Contact {
        let a: Bot
        let b: Bot
    }

    static func advance(_ bots: [Bot], now: Double, dt: Double) -> [Contact] {
        guard dt > 0, dt.isFinite else { return [] }
        let steps = max(1, Int(ceil(dt / (1.0 / 120))))
        let step = dt / Double(steps)
        var contacts: [String: Contact] = [:]
        for index in 0..<steps {
            let time = now - dt + Double(index + 1) * step
            for bot in bots { bot.separate(from: bots) }
            for bot in bots { bot.step(now: time, dt: step) }
            for contact in resolve(bots, now: time) {
                contacts["\(min(contact.a.id, contact.b.id)):\(max(contact.a.id, contact.b.id))"] = contact
            }
        }
        return Array(contacts.values)
    }

    // Circular colliders enclose the rotated body and legs. This runs independently
    // of personality, talking, or social cooldowns, including when both bots are fleeing.
    static func resolve(_ bots: [Bot], now: Double) -> [Contact] {
        guard bots.count > 1 else { return [] }
        var contacts: [String: Contact] = [:]
        for _ in 0..<24 {
            var overlapping = false
            for i in 0..<(bots.count - 1) {
                for j in (i + 1)..<bots.count {
                    let a = bots[i]
                    let b = bots[j]
                    guard a.screenIndex == b.screenIndex else { continue }
                    if a.planted && b.planted {
                        let distance = hypot(b.x - a.x, b.y - a.y)
                        let required = a.collisionRadius + b.collisionRadius
                        guard distance < required * 0.55 else { continue }
                    }
                    let dx = b.x - a.x
                    let dy = b.y - a.y
                    let distance = hypot(dx, dy)
                    let required = a.collisionRadius + b.collisionRadius
                    guard distance < required - 0.001 else { continue }
                    overlapping = true
                    let normal: CGPoint
                    if distance > 0.0001 {
                        normal = CGPoint(x: dx / distance, y: dy / distance)
                    } else {
                        let angle = CGFloat((a.id * 31 + b.id * 17) % 360) * .pi / 180
                        normal = CGPoint(x: cos(angle), y: sin(angle))
                    }
                    let depth = required - distance + 0.001
                    let inverseA = 1 / (a.collisionRadius * a.collisionRadius)
                    let inverseB = 1 / (b.collisionRadius * b.collisionRadius)
                    let shareA = inverseA / (inverseA + inverseB)
                    let awayA = CGPoint(x: -normal.x, y: -normal.y)
                    let spaceA = availableDistance(a, direction: awayA)
                    let spaceB = availableDistance(b, direction: normal)
                    var moveA = min(depth * shareA, spaceA)
                    let moveB = min(depth - moveA, spaceB)
                    moveA = min(depth - moveB, spaceA)
                    a.x -= normal.x * moveA
                    a.y -= normal.y * moveA
                    b.x += normal.x * moveB
                    b.y += normal.y * moveB
                    a.clampHome()
                    b.clampHome()
                    a.deflect(away: CGPoint(x: -normal.x, y: -normal.y), now: now)
                    b.deflect(away: normal, now: now)
                    contacts["\(i):\(j)"] = Contact(a: a, b: b)
                }
            }
            if !overlapping { break }
        }
        return Array(contacts.values)
    }

    private static func availableDistance(_ bot: Bot, direction: CGPoint) -> CGFloat {
        let bounds = bot.home.insetBy(dx: 28, dy: 28)
        var distance = CGFloat.greatestFiniteMagnitude
        if direction.x > 0.00001 { distance = min(distance, (bounds.maxX - bot.x) / direction.x) }
        if direction.x < -0.00001 { distance = min(distance, (bounds.minX - bot.x) / direction.x) }
        if direction.y > 0.00001 { distance = min(distance, (bounds.maxY - bot.y) / direction.y) }
        if direction.y < -0.00001 { distance = min(distance, (bounds.minY - bot.y) / direction.y) }
        return max(0, distance)
    }
}

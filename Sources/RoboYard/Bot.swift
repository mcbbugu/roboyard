import AppKit
import QuartzCore

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
    var scareCool: CFTimeInterval = 0
    var petCool: CFTimeInterval = 0
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

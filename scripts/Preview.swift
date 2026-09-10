import AppKit
import QuartzCore
import ImageIO
import UniformTypeIdentifiers

// Documentation-only scene: synthetic memories, real renderer and collision code.
// It never reads or writes a user's memory store and never calls a model.
@main struct Preview {
    @MainActor static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let home = NSRect(x: 0, y: 0, width: 380, height: 140)
        let totals = [0, 2_000, 20_000, 100_000]
        var bots: [Bot] = []
        for (index, total) in totals.enumerated() {
            let memory = RobotMemory(id: index + 1, personality: MBTI.intp.rawValue)
            var remaining = total
            var batch = 0
            while remaining > 0 {
                let count = min(160, remaining)
                memory.remember(.speech, detail: String(repeating: "字", count: count), now: Date(timeIntervalSince1970: Double(batch) * 10))
                batch += 1
                remaining -= count
            }
            let bot = Bot(id: index + 1, mbti: .intp, home: home, screenIndex: 0, memory: memory)
            bot.x = [55, 135, 175, 305][index]
            bot.y = [72, 70, 72, 80][index]
            bot.heading = [0, 0, .pi, .pi][index]
            bot.targetHeading = bot.heading
            bot.angle = bot.heading - .pi / 2
            bot.speed = index == 3 ? 0 : 20
            bot.targetSpeed = bot.speed
            bot.act = index == 3 ? .stand : .walk
            bot.actUntil = 1000
            bot.steerUntil = 1000
            bots.append(bot)
        }
        for frame in 0..<96 {
            let time = Double(frame) / 12
            for substep in 0..<10 {
                _ = BotPhysics.advance(bots, now: time + Double(substep) / 120, dt: 1.0 / 120)
            }
            try bitmap(width: 960, height: 560, to: output.appendingPathComponent(String(format: "%03d.png", frame))) {
                color(0x10131d).setFill()
                NSRect(x: 0, y: 0, width: 960, height: 560).fill()
                label("ROBOYARD", at: CGPoint(x: 44, y: 505), size: 16, weight: .bold, ink: color(0xa8a0ff))
                label("Your desktop. Their playground.", at: CGPoint(x: 44, y: 444), size: 36, weight: .semibold, ink: .white)
                let world = NSRect(x: 44, y: 116, width: 872, height: 290)
                color(0x1b2130).setFill()
                NSBezierPath(roundedRect: world, xRadius: 20, yRadius: 20).fill()
                color(0x30384e).setStroke()
                NSBezierPath(roundedRect: world, xRadius: 20, yRadius: 20).stroke()
                label("ROAMING / COLLISIONS / CHAT / GROWTH", at: CGPoint(x: 64, y: 380), size: 11, weight: .medium, ink: color(0x919aae))
                let ctx = NSGraphicsContext.current!.cgContext
                ctx.saveGState()
                ctx.translateBy(x: 74, y: 110)
                ctx.scaleBy(x: 2.1, y: 2.1)
                for bot in bots {
                    let size = bot.bodySize
                    ctx.saveGState()
                    ctx.translateBy(x: bot.x, y: bot.y)
                    ctx.rotate(by: bot.angle)
                    RobotMark.drawBot(in: CGRect(x: -size / 2, y: -size / 2, width: size, height: size), lid: RobotMark.lid(at: time), gait: bot.gait, speed: bot.speed, sit: bot.sit)
                    ctx.restoreGState()
                }
                ctx.restoreGState()
                if frame >= 18 && frame <= 82 {
                    let bubble = NSRect(x: 630, y: 326, width: 238, height: 34)
                    color(0xb3aaff).setFill()
                    NSBezierPath(roundedRect: bubble, xRadius: 12, yRadius: 12).fill()
                    label("嘿，你撞到我啦！", at: CGPoint(x: 648, y: 334), size: 16, weight: .medium, ink: color(0x151322))
                }
                label("COLLIDE  →  TALK  →  REMEMBER  →  GROW", at: CGPoint(x: 44, y: 65), size: 15, weight: .semibold, ink: color(0xe1defb))
                label("Scripted preview · seeded memories · real rendering & physics", at: CGPoint(x: 44, y: 34), size: 12, weight: .regular, ink: color(0x929aaf))
            }
        }
        let gif = CGImageDestinationCreateWithURL(output.appendingPathComponent("world.gif") as CFURL,
                                                  UTType.gif.identifier as CFString, 96, nil)!
        CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for frame in 0..<96 {
            let url = output.appendingPathComponent(String(format: "%03d.png", frame))
            let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
            CGImageDestinationAddImage(gif, CGImageSourceCreateImageAtIndex(source, 0, nil)!,
                                      [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / 12]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(gif) else { throw CocoaError(.fileWriteUnknown) }
        try bitmap(width: 1280, height: 480, to: output.appendingPathComponent("hero.png")) {
            color(0x151927).setFill()
            NSRect(x: 0, y: 0, width: 1280, height: 480).fill()
            label("TURN YOUR DESKTOP INTO A ROBOT PLAYGROUND", at: CGPoint(x: 64, y: 400), size: 17, weight: .semibold, ink: color(0xb4a9ff))
            label("RoboYard", at: CGPoint(x: 58, y: 278), size: 96, weight: .bold, ink: color(0xf5f3ff))
            label("They roam. They bump.", at: CGPoint(x: 64, y: 211), size: 32, weight: .regular, ink: color(0xd6d3e5))
            label("They chat. They grow.", at: CGPoint(x: 64, y: 169), size: 32, weight: .regular, ink: color(0xd6d3e5))
            label("NATIVE macOS  /  LOCAL AI  /  OPEN SOURCE", at: CGPoint(x: 66, y: 67), size: 15, weight: .medium, ink: color(0x9099ae))
            for (i, size) in [CGFloat(48), 76, 116].enumerated() {
                RobotMark.drawBot(in: CGRect(x: [790, 930, 1080][i], y: 140, width: size, height: size), lid: 0, gait: 0, speed: 0)
            }
            label("ROAM", at: CGPoint(x: 774, y: 105), size: 12, weight: .medium, ink: color(0x929aae))
            label("BUMP & CHAT", at: CGPoint(x: 934, y: 105), size: 12, weight: .medium, ink: color(0x929aae))
            label("GROW", at: CGPoint(x: 1087, y: 105), size: 12, weight: .medium, ink: color(0xc6baff))
            color(0x2b2542).setFill()
            NSBezierPath(roundedRect: NSRect(x: 974, y: 320, width: 246, height: 76), xRadius: 16, yRadius: 16).fill()
            label("Hey, watch", at: CGPoint(x: 997, y: 361), size: 18, weight: .medium, ink: color(0xe5dfff))
            label("where you’re going!", at: CGPoint(x: 997, y: 336), size: 18, weight: .medium, ink: color(0xe5dfff))
        }
        try bitmap(width: 1024, height: 1024, to: output.appendingPathComponent("icon.png")) {
            color(0x191d2b).setFill()
            NSBezierPath(roundedRect: NSRect(x: 70, y: 70, width: 884, height: 884), xRadius: 200, yRadius: 200).fill()
            color(0xb3aaff).setFill()
            NSBezierPath(ovalIn: NSRect(x: 636, y: 675, width: 110, height: 110)).fill()
            RobotMark.drawBot(in: CGRect(x: 220, y: 236, width: 530, height: 530), lid: 0, gait: 0, speed: 0)
        }
    }

    @MainActor static func bitmap(width: Int, height: Int, to url: URL, draw: () -> Void) throws {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw()
        NSGraphicsContext.restoreGraphicsState()
        try rep.representation(using: .png, properties: [:])!.write(to: url)
    }

    static func color(_ hex: Int) -> NSColor {
        NSColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
    }

    @MainActor static func label(_ text: String, at point: CGPoint, size: CGFloat, weight: NSFont.Weight, ink: NSColor) {
        (text as NSString).draw(at: point, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: ink])
    }
}

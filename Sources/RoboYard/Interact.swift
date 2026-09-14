import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// 2.0 interaction laws: petting, feeding, renaming. Pure and testable.
enum PetLaw {
    static let clickKey = "critter.petclick"
    static let radius: CGFloat = 56
    static let cooldown: CFTimeInterval = 3.0
    static let chargeGain = 0.01
    static let feedGain = 0.08
    static let feedCooldown: CFTimeInterval = 60
    static func canPet(lastPet: CFTimeInterval, now: CFTimeInterval) -> Bool {
        now - lastPet >= cooldown
    }

    static func canFeed(lastFeed: CFTimeInterval, now: CFTimeInterval) -> Bool {
        now - lastFeed >= feedCooldown
    }

    /// Nearest bot id within touch radius, if any.
    static func target(at point: CGPoint, among bots: [(id: Int, point: CGPoint)]) -> Int? {
        var best: Int?
        var bestD = radius
        for b in bots {
            let d = hypot(b.point.x - point.x, b.point.y - point.y)
            if d < bestD { bestD = d; best = b.id }
        }
        return best
    }
}

/// 5.1 scare bands (fixes #4): position alone can't tell a chase from a
/// sneak, so the outer band is velocity-gated. Touch band always scares.
enum ScareLaw {
    static let touchRadius: CGFloat = 14
    static let scareRadius: CGFloat = 36
    static let speedThreshold: CGFloat = 250
    static let calmAfterPet: CFTimeInterval = 1.5

    static func shouldScare(distance: CGFloat, speed: CGFloat) -> Bool {
        if distance < touchRadius { return true }
        if distance < scareRadius, speed > speedThreshold { return true }
        return false
    }
}

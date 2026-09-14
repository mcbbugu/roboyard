import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

@MainActor
final class Colonist {
    let id: Int
    let memory: RobotMemory
    var charge: Double
    var post: ChargeLaw.Post
    var bot: Bot?
    var highlightUntil: CFTimeInterval = 0

    init(id: Int, memory: RobotMemory, charge: Double, post: ChargeLaw.Post = .warehouse) {
        self.id = id
        self.memory = memory
        self.charge = ChargeLaw.clamp(charge)
        self.post = post
    }

    var name: String { memory.name }
    var mbti: MBTI { memory.mbti }
}

enum ChargeStore {
    static let key = "critter.charges"

    static func load() -> [Int: Double] {
        guard let raw = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] else { return [:] }
        var table: [Int: Double] = [:]
        for (key, value) in raw {
            guard let id = Int(key) else { continue }
            table[id] = ChargeLaw.clamp(value)
        }
        return table
    }

    @MainActor
    static func save(_ colonists: [Colonist]) {
        var table: [String: Double] = [:]
        for colonist in colonists {
            table["\(colonist.id)"] = ChargeLaw.clamp(colonist.charge)
        }
        UserDefaults.standard.set(table, forKey: key)
    }

    static func seed(id: Int) -> Double {
        let u = Double((id * 47 + 13) % 100) / 100
        return ChargeLaw.clamp(0.38 + 0.55 * u)
    }
}

struct YardRow: Identifiable {
    let id: Int
    let name: String
    let code: String
    let stage: String
    let charge: Double
    let post: ChargeLaw.Post
    let refused: Bool
    let bodySize: Double
    let worldVisible: Bool
    let friendBadge: String?

    var tired: CGFloat { CGFloat(1 - ChargeLaw.limp(for: charge)) }

    /// Estimated minutes left on the desk at walking drain. Nil when charging.
    var minutesLeft: Int? {
        guard post != .warehouse else { return nil }
        let usable = max(0, charge - ChargeLaw.goHomeBelow)
        return Int((usable / ChargeLaw.walkDrain) / 60)
    }

    var canToggle: Bool {
        guard worldVisible else { return false }
        switch post {
        case .warehouse: return charge >= ChargeLaw.talkBelow
        case .homing: return false
        case .yard, .emerging: return true
        }
    }

    var action: String {
        Copy.ui.action(post: post, refused: refused, charged: charge >= ChargeLaw.talkBelow,
                       worldVisible: worldVisible)
    }
    var hint: String { Copy.ui.hint(post: post, canToggle: canToggle, worldVisible: worldVisible) }
}

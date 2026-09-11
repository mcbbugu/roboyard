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

    var tired: CGFloat { CGFloat(1 - ChargeLaw.limp(for: charge)) }

    var canToggle: Bool {
        switch post {
        case .warehouse: charge >= ChargeLaw.talkBelow
        case .homing: false
        case .yard, .emerging: true
        }
    }

    var action: String {
        if refused, post == .yard { return "叫回来" }
        switch post {
        case .warehouse: return charge >= ChargeLaw.talkBelow ? "派上桌" : "充电中"
        case .yard: return "叫回来"
        case .homing: return "正在回家"
        case .emerging: return "正在出门"
        }
    }

    var hint: String {
        switch post {
        case .warehouse:
            return canToggle ? "从仓库派到桌上。桌上满了会换走电最少的。" : "电还没够，充好会自己出来。"
        case .yard:
            return "叫回仓库充电。不是点桌面上的机器人。"
        case .homing:
            return "正往菜单栏走，到了就进仓库消失。"
        case .emerging:
            return "刚从仓库爬出来。点一下叫回去。"
        }
    }
}

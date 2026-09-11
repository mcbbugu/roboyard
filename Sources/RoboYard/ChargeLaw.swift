import Foundation

enum ChargeLaw {
    static let roster = 32
    static let goHomeBelow = 0.12
    static let emergeAbove = 0.88
    static let talkBelow = 0.22
    static let limpBelow = 0.20
    static let crawlBelow = 0.08
    static let warehouseFill = 1.0 / 32
    static let walkDrain = 1.0 / 210
    static let sitDrain = 1.0 / 960
    static let fleeDrain = 1.0 / 36
    static let talkCost = 0.04
    static let bumpCost = 0.018
    static let scareCost = 0.028
    static let sharePerSec = 0.06
    static let shareRadius = 40.0

    enum Post: String, Equatable, CaseIterable {
        case yard, homing, warehouse, emerging

        var onDesk: Bool {
            self == .yard || self == .homing || self == .emerging
        }

        var title: String {
            switch self {
            case .yard: "在桌上"
            case .homing: "往回爬"
            case .warehouse: "仓库里"
            case .emerging: "爬出来"
            }
        }
    }

    static func clamp(_ value: Double) -> Double { min(1, max(0, value)) }

    static func fill(_ charge: Double, dt: Double) -> Double {
        clamp(charge + dt * warehouseFill)
    }

    static func drain(_ charge: Double, dt: Double, speed: Double, fleeing: Bool, sitting: Bool, refused: Bool) -> Double {
        let rest = refused ? 0.35 : 1
        if fleeing { return clamp(charge - dt * fleeDrain * rest) }
        if sitting { return clamp(charge - dt * sitDrain * rest) }
        let motion = min(1, max(0, speed / 58))
        return clamp(charge - dt * walkDrain * (0.35 + 0.65 * motion) * rest)
    }

    static func share(rich: Double, poor: Double, dt: Double) -> (Double, Double) {
        guard rich > poor + 0.04 else { return (rich, poor) }
        let moved = min(sharePerSec * dt, (rich - poor) / 2)
        return (clamp(rich - moved), clamp(poor + moved))
    }

    static func limp(for charge: Double) -> Double {
        if charge <= crawlBelow { return 0.22 }
        if charge <= limpBelow { return 0.5 }
        return 1
    }

    static func canTalk(_ charge: Double) -> Bool { charge >= talkBelow }

    static func shouldGoHome(_ charge: Double, post: Post) -> Bool {
        post == .yard && charge <= goHomeBelow
    }

    static func shouldLeaveStall(_ charge: Double) -> Bool { charge >= emergeAbove }

    static func pickRelease(from warehouse: [(id: Int, charge: Double)], cap: Int, onYard: Int) -> Int? {
        guard onYard < cap else { return nil }
        return warehouse.filter { $0.charge >= emergeAbove }.max { $0.charge < $1.charge }?.id
    }

    static func pickSwap(onYard: [(id: Int, charge: Double)]) -> Int? {
        onYard.min { $0.charge < $1.charge }?.id
    }
}

import AppKit
import Testing
@testable import RoboYard

struct RobotMarkTests {
    private func rgb(_ color: NSColor) -> (CGFloat, CGFloat, CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.usingColorSpace(.sRGB)!.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b)
    }

    private func same(_ a: NSColor, _ b: NSColor) -> Bool {
        let x = rgb(a), y = rgb(b)
        return abs(x.0 - y.0) < 0.01 && abs(x.1 - y.1) < 0.01 && abs(x.2 - y.2) < 0.01
    }

    @Test
    func eachGroupGetsItsOwnAccent() {
        let nt = RobotMark.accent(for: "NT")
        let nf = RobotMark.accent(for: "NF")
        let sj = RobotMark.accent(for: "SJ")
        let sp = RobotMark.accent(for: "SP")
        #expect(!same(nt, nf) && !same(nt, sj) && !same(nt, sp))
        #expect(!same(nf, sj) && !same(nf, sp) && !same(sj, sp))
        #expect(same(RobotMark.accent(for: "??"), RobotMark.accent(for: "")))
    }

    @Test
    func energyTintFollowsChargeThresholds() {
        #expect(same(RobotMark.energyTint(0.05), RobotMark.energyTint(ChargeLaw.goHomeBelow)))
        #expect(same(RobotMark.energyTint(0.15), RobotMark.energyTint(ChargeLaw.talkBelow)))
        #expect(same(RobotMark.energyTint(0.95), RobotMark.energyTint(ChargeLaw.emergeAbove)))
        #expect(!same(RobotMark.energyTint(0.05), RobotMark.energyTint(0.5)))
        #expect(!same(RobotMark.energyTint(0.5), RobotMark.energyTint(0.95)))
    }
}

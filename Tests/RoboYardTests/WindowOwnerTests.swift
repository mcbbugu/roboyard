import AppKit
import Testing
@testable import RoboYard

struct WindowOwnerTests {
    let primary = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    @Test
    func convertsCocoaPointsOnPrimaryAndNeighborScreens() {
        #expect(WindowOwner.quartzPoint(cocoa: CGPoint(x: 100, y: 80), primaryFrame: primary)
            == CGPoint(x: 100, y: 1000))
        #expect(WindowOwner.quartzPoint(cocoa: CGPoint(x: 2000, y: 100), primaryFrame: primary)
            == CGPoint(x: 2000, y: 980))
        #expect(WindowOwner.quartzPoint(cocoa: CGPoint(x: 100, y: 1500), primaryFrame: primary)
            == CGPoint(x: 100, y: -420))
    }

    @Test
    func picksFrontmostLayerZeroWindowAndSkipsSelf() {
        let safari = WindowOwner.Record(layer: 0, owner: "Safari", bounds: CGRect(x: 0, y: 0, width: 800, height: 600))
        let xcode = WindowOwner.Record(layer: 0, owner: "Xcode", bounds: CGRect(x: 0, y: 0, width: 800, height: 600))
        let selfApp = WindowOwner.Record(layer: 0, owner: "RoboYard", bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let menu = WindowOwner.Record(layer: 25, owner: "Window Server", bounds: CGRect(x: 0, y: 0, width: 1920, height: 24))
        let cocoa = CGPoint(x: 40, y: 800)
        let front = WindowOwner.name(
            atCocoa: cocoa, primaryFrame: primary,
            windows: [selfApp, menu, safari, xcode],
            skip: ["RoboYard"], fallback: "Finder"
        )
        #expect(front == "Safari")
    }

    @Test
    func fallsBackWhenNoWindowContainsThePoint() {
        let window = WindowOwner.Record(layer: 0, owner: "Safari", bounds: CGRect(x: 0, y: 0, width: 200, height: 200))
        let name = WindowOwner.name(
            atCocoa: CGPoint(x: 900, y: 500), primaryFrame: primary,
            windows: [window], skip: ["RoboYard"], fallback: "Finder"
        )
        #expect(name == "Finder")
    }
}

import Foundation
import Testing
@testable import RoboYard

struct ChargeLawTests {
    @Test
    func potentialEndsAreQuietAndTheMiddleTalks() {
        #expect(ChargeLaw.canTalk(0.5))
        #expect(!ChargeLaw.canTalk(ChargeLaw.goHomeBelow))
        #expect(ChargeLaw.shouldGoHome(ChargeLaw.goHomeBelow, post: .yard))
        #expect(!ChargeLaw.shouldGoHome(0.5, post: .yard))
        #expect(!ChargeLaw.shouldGoHome(0, post: .warehouse))
        #expect(ChargeLaw.shouldLeaveStall(ChargeLaw.emergeAbove))
        #expect(!ChargeLaw.shouldLeaveStall(0.4))
    }

    @Test
    func walkingDrainsAndTheNestFills() {
        let walked = ChargeLaw.drain(1, dt: 10, speed: 50, fleeing: false, sitting: false, refused: false)
        let sat = ChargeLaw.drain(1, dt: 10, speed: 0, fleeing: false, sitting: true, refused: false)
        let fled = ChargeLaw.drain(1, dt: 2, speed: 90, fleeing: true, sitting: false, refused: false)
        #expect(walked < sat)
        #expect(fled < walked)
        let filled = ChargeLaw.fill(0, dt: 32)
        #expect(filled >= 0.95)
        let refused = ChargeLaw.drain(1, dt: 10, speed: 50, fleeing: false, sitting: false, refused: true)
        #expect(refused > walked)
        let reserve = ChargeLaw.drain(ChargeLaw.goHomeBelow, dt: 300, speed: 38,
                                      fleeing: false, sitting: false, refused: false, post: .homing)
        #expect(reserve == ChargeLaw.goHomeBelow)
    }

    @Test
    func fullChargeWalksForThirtyMinutesBeforeHeadingHome() {
        let before = ChargeLaw.drain(1, dt: 30 * 60 - 1, speed: 38,
                                     fleeing: false, sitting: false, refused: false)
        let due = ChargeLaw.drain(1, dt: 30 * 60, speed: 38,
                                  fleeing: false, sitting: false, refused: false)
        #expect(!ChargeLaw.shouldGoHome(before, post: .yard))
        #expect(abs(due - ChargeLaw.goHomeBelow) < 0.000_001)
        #expect(ChargeLaw.shouldGoHome(due, post: .yard))
    }

    @Test
    func sharingMovesChargeTowardThePoorerOfAPair() {
        let next = ChargeLaw.share(rich: 0.8, poor: 0.2, dt: 1)
        #expect(next.0 < 0.8)
        #expect(next.1 > 0.2)
        let even = ChargeLaw.share(rich: 0.5, poor: 0.5, dt: 1)
        #expect(even.0 == 0.5)
    }

    @Test
    func theWarehouseReleasesTheFullestWhenTheYardHasRoom() {
        let warehouse = [(1, 0.4), (2, 0.95), (3, 0.99)]
        #expect(ChargeLaw.pickRelease(from: warehouse, cap: 8, onYard: 8) == nil)
        #expect(ChargeLaw.pickRelease(from: warehouse, cap: 8, onYard: 7) == 3)
        #expect(ChargeLaw.pickSwap(onYard: [(4, 0.2), (5, 0.9)]) == 4)
        #expect(ChargeLaw.limp(for: 0.05) < ChargeLaw.limp(for: 0.5))
    }

    @Test
    func releaseDoesNotLoopWhenHomingFillsTheCap() {
        let warehouse = [(1, 0.99)]
        #expect(ChargeLaw.pickRelease(from: warehouse, cap: 8, onYard: 2) == 1)
        #expect(ChargeLaw.pickSwap(onYard: []) == nil)
    }
}

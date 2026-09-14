import Foundation
import Testing
@testable import RoboYard

@MainActor
struct InteractTests {
    @Test
    func petAndFeedCooldowns() {
        #expect(PetLaw.canPet(lastPet: 0, now: 3) == true)
        #expect(PetLaw.canPet(lastPet: 0, now: 2.9) == false)
        #expect(PetLaw.canFeed(lastFeed: 0, now: 60) == true)
        #expect(PetLaw.canFeed(lastFeed: 0, now: 59) == false)
        #expect(PetLaw.chargeGain == 0.01)
        #expect(PetLaw.feedGain == 0.08)
    }

    @Test
    func clickTargetsNearestBotInRadius() {
        let bots = [(id: 1, point: CGPoint(x: 0, y: 0)), (id: 2, point: CGPoint(x: 100, y: 0))]
        #expect(PetLaw.target(at: CGPoint(x: 10, y: 0), among: bots) == 1)
        #expect(PetLaw.target(at: CGPoint(x: 90, y: 0), among: bots) == 2)
        #expect(PetLaw.target(at: CGPoint(x: 500, y: 500), among: bots) == nil)
        #expect(PetLaw.target(at: CGPoint(x: 0, y: 0), among: []) == nil)
    }

    @Test
    func nicknameOverridesNumberAndClears() {
        let m = RobotMemory(id: 3, personality: MBTI.infp.rawValue)
        #expect(m.name == Copy(lang: .zh).robot(3))
        m.nickname = "  阿铁  "
        #expect(m.name == "阿铁")
        m.nickname = String(repeating: "字", count: 20)
        #expect(m.name.count == 12)
        m.nickname = "   "
        #expect(m.name == Copy(lang: .zh).robot(3))
    }

    @Test
    func careMemoriesAreDebounced() {
        let m = RobotMemory(id: 4, personality: MBTI.intp.rawValue)
        let now = Date(timeIntervalSince1970: 5000)
        #expect(m.remember(.care, subject: "petted", detail: "被摸了", now: now))
        #expect(!m.remember(.care, subject: "petted", detail: "被摸了", now: now.addingTimeInterval(10)))
        #expect(m.remember(.care, subject: "petted", detail: "又被摸了", now: now.addingTimeInterval(31)))
    }

    @Test
    func preNicknameArchivesStillDecode() throws {
        let json = #"{"id":5,"personality":3,"bornAt":1000}"#
        let m = try JSONDecoder().decode(RobotMemory.self, from: Data(json.utf8))
        #expect(m.id == 5)
        #expect(m.nickname == nil)
        #expect(m.name == Copy(lang: .zh).robot(5))
        #expect(m.textCount == 0)
    }

    @Test
    func nicknameSurvivesSaveAndReload() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("memories.json")
        let store = RobotMemoryStore(fileURL: url)
        store.profile(id: 6).nickname = "小电"
        store.save()
        let reloaded = RobotMemoryStore(fileURL: url)
        #expect(reloaded.errorMessage == nil)
        #expect(reloaded.profile(id: 6).nickname == "小电")
        #expect(reloaded.profile(id: 6).name == "小电")
    }

    @Test
    func petLinesAreStablePerRobot() {
        #expect(Copy(lang: .zh).petLine(1) == Copy(lang: .zh).petLine(1))
        #expect(Copy(lang: .en).petLine(1).isEmpty == false)
    }
}

struct ScareBandTests {
    @Test
    func touchAlwaysScaresOuterBandNeedsSpeed() {
        #expect(ScareLaw.shouldScare(distance: 0, speed: 0) == true)
        #expect(ScareLaw.shouldScare(distance: 13.9, speed: 0) == true)
        #expect(ScareLaw.shouldScare(distance: 14, speed: 0) == false)
        #expect(ScareLaw.shouldScare(distance: 20, speed: 0) == false)
        #expect(ScareLaw.shouldScare(distance: 20, speed: 250) == false)
        #expect(ScareLaw.shouldScare(distance: 20, speed: 251) == true)
        #expect(ScareLaw.shouldScare(distance: 35.9, speed: 1000) == true)
        #expect(ScareLaw.shouldScare(distance: 36, speed: 1000) == false)
        #expect(ScareLaw.shouldScare(distance: 100, speed: 4000) == false)
        #expect(ScareLaw.calmAfterPet == 1.5)
    }
}

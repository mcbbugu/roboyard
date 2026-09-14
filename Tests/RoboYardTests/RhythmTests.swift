import Foundation
import Testing
@testable import RoboYard

struct RhythmTests {
    @Test
    func quietCoversOvernightHours() {
        #expect(Rhythm.isQuiet(date: Rhythm.date(hour: 23)) == true)
        #expect(Rhythm.isQuiet(date: Rhythm.date(hour: 0)) == true)
        #expect(Rhythm.isQuiet(date: Rhythm.date(hour: 6)) == true)
        #expect(Rhythm.isQuiet(date: Rhythm.date(hour: 7)) == false)
        #expect(Rhythm.isQuiet(date: Rhythm.date(hour: 12)) == false)
        #expect(Rhythm.isQuiet(date: Rhythm.date(hour: 22)) == false)
    }

    @Test
    func grudgesSurfaceAfterRepeatedCollisions() {
        let zh = Copy(lang: .zh)
        #expect(zh.scoldCueFor(other: "伙伴", collisions: 0).contains("追着") == true)
        #expect(zh.scoldCueFor(other: "伙伴", collisions: 5).contains("追着") == true)
        let grudge = zh.scoldCueFor(other: "伙伴", collisions: 6)
        #expect(grudge.contains("6") == true)
        #expect(grudge != zh.scoldCue("伙伴"))
        let en = Copy(lang: .en).scoldCueFor(other: "pal", collisions: 9)
        #expect(en.contains("9") == true)
    }

    @Test
    func collisionsAccumulatePerRival() {
        let m = RobotMemory(id: 8, personality: MBTI.estp.rawValue)
        #expect(m.collisions(with: 9) == 0)
        var tick = Date(timeIntervalSince1970: 0)
        m.meet(9, friendly: false, now: tick)
        #expect(m.collisions(with: 9) == 1)
        tick = tick.addingTimeInterval(20)
        m.meet(9, friendly: false, now: tick)
        #expect(m.collisions(with: 9) == 2)
        #expect(m.meetings(with: 9) == 0)
    }
}

struct ShipTests {
    @Test
    func logRotationAndFormatting() {
        #expect(Log.needsRotation(size: 0) == false)
        #expect(Log.needsRotation(size: Log.maxBytes) == false)
        #expect(Log.needsRotation(size: Log.maxBytes + 1) == true)
        #expect(Log.formatted("hi").contains("hi") == true)
        #expect(Log.formatted("hi").hasPrefix("[") == true)
    }

    @Test
    func logWritesToInjectedDirectory() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        Log.add("hello-yard", in: folder)
        Log.add("second", in: folder)
        let text = try String(contentsOf: Log.fileURL(in: folder), encoding: .utf8)
        #expect(text.contains("hello-yard") == true)
        #expect(text.contains("second") == true)
    }

    @Test
    func deskCapNowReachesTwentyFour() {
        #expect(Critters.countChoices.contains(24) == true)
    }
}

@MainActor
struct ReunionTests {
    @Test
    func gapTracksAbsenceBetweenEncounters() {
        let m = RobotMemory(id: 10, personality: MBTI.enfp.rawValue)
        #expect(m.gap(with: 11) == nil)
        let t0 = Date(timeIntervalSince1970: 1000)
        m.meet(11, friendly: true, now: t0)
        #expect(m.gap(with: 11) == nil)
        m.meet(11, friendly: true, now: t0.addingTimeInterval(100_000))
        #expect(abs((m.gap(with: 11) ?? 0) - 100_000) < 0.01)
    }

    @Test
    func reunionOpenerNeedsADayAndHistory() {
        let zh = Copy(lang: .zh)
        let fresh = zh.reunionOpen(other: "伙伴", gapDays: 3, memory: "又和11号聊了一会儿")
        #expect(fresh.contains("3") == true)
        #expect(fresh.contains("又和11号聊了一会儿") == true)
        #expect(zh.reunionOpen(other: "伙伴", gapDays: 1, memory: nil).contains("重逢") == true)
        #expect(CritterTalk.reunionAfter == 86_400)
    }

    @Test
    func reminiscenceQuotesTheOldestSharedLine() {
        let m = RobotMemory(id: 12, personality: MBTI.intj.rawValue)
        #expect(m.reminiscence(about: 13) == nil)
        var tick = Date(timeIntervalSince1970: 2000)
        m.meet(13, friendly: true, now: tick, lang: .zh)
        tick = tick.addingTimeInterval(20)
        m.meet(14, friendly: true, now: tick, lang: .zh)
        let first = m.reminiscence(about: 13)
        #expect(first?.contains("13号") == true)
        #expect(m.reminiscence(about: 14)?.contains("14号") == true)
        #expect(m.reminiscence(about: 99) == nil)
    }

    @Test
    func bareRelationshipJSONStillDecodes() throws {
        let r = try JSONDecoder().decode(RobotRelationship.self, from: Data("{}".utf8))
        #expect(r.meetings == 0 && r.collisions == 0)
        #expect(r.gap == nil && r.lastMet == nil)
    }
}

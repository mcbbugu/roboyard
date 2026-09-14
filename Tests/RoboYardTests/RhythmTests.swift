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

import Foundation
import Testing
@testable import RoboYard

@MainActor
struct RobotMemoryTests {
    @Test
    func growthCountsTextAndNotAgeOrContactFrames() {
        let memory = RobotMemory(id: 1, personality: MBTI.intj.rawValue,
                                 bornAt: Date(timeIntervalSince1970: 0))
        #expect(memory.textCount == 0)
        #expect(memory.bodySize() == 16)
        #expect(memory.stage() == .newborn)
        let now = Date(timeIntervalSince1970: 1000)
        #expect(memory.remember(.collision, subject: "2", detail: "碰到你了", now: now))
        #expect(memory.textCount == 4)
        for _ in 0..<60 {
            #expect(!memory.remember(.collision, subject: "2", detail: "碰到你了", now: now))
        }
        #expect(memory.textCount == 4)
        #expect(memory.bodySize() > 16)
        memory.remember(.speech, detail: "世界外面是什么", now: now)
        #expect(memory.textCount == 11)
    }

    @Test
    func accumulatedLanguageChangesStageAndKeepsPromptBounded() {
        let memory = grownMemory(id: 1)
        #expect(memory.textCount == RobotMemory.awakeningTextCount)
        #expect(memory.stage() == .awakened)
        #expect(memory.bodySize() == 32)
        #expect(memory.experiences.count == 32)
        #expect(memory.archivePending.count == 625)
        #expect(memory.context().count <= 1400)
        #expect(memory.context().contains("二维世界"))
    }

    @Test
    func oldFriendsTalkLongerThanStrangers() {
        let memory = RobotMemory(id: 1, personality: MBTI.infp.rawValue)
        #expect(memory.chatRounds(with: 2, pal: false) == 1)
        #expect(memory.chatRounds(with: 2, pal: true) == 2)
        var tick = Date(timeIntervalSince1970: 0)
        for _ in 0..<9 {
            tick = tick.addingTimeInterval(20)
            memory.meet(2, friendly: true, now: tick)
        }
        #expect(memory.meetings(with: 2) == 9)
        #expect(memory.chatRounds(with: 2, pal: false) == 4)
        #expect(memory.chatRounds(with: 2, pal: true) == 5)
    }

    @Test
    func retrievesRelevantExperienceAfterItLeavesRecentMemory() {
        let memory = RobotMemory(id: 1, personality: MBTI.infp.rawValue)
        let start = Date(timeIntervalSince1970: 1000)
        memory.meet(2, friendly: true, now: start)
        for i in 0..<40 {
            memory.remember(.speech, subject: "self", detail: "今天又走了一段路",
                            now: start.addingTimeInterval(Double(i + 1) * 10))
        }
        #expect(!memory.experiences.contains { $0.kind == .friend })
        #expect(memory.context(kind: .friend, subject: "2").contains("又和2号聊了一会儿"))
    }

    @Test
    func savesIdentitiesTextAndCompleteHistoryWithoutDuplicateArchiveEntries() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("memories.json")
        let store = RobotMemoryStore(fileURL: url)
        let memory = store.profile(id: 1)
        for i in 0..<50 {
            memory.remember(.speech, subject: "self", detail: "这是我的第\(i)句话",
                            now: Date(timeIntervalSince1970: Double(i) * 10))
        }
        let textCount = memory.textCount
        let personality = memory.personality
        store.save()
        #expect(store.errorMessage == nil)
        let reloaded = RobotMemoryStore(fileURL: url)
        #expect(reloaded.errorMessage == nil)
        #expect(reloaded.profile(id: 1).textCount == textCount)
        #expect(reloaded.profile(id: 1).personality == personality)
        #expect(reloaded.profile(id: 1) === reloaded.profile(id: 1))
        #expect(reloaded.profile(id: 1).archivePending.isEmpty)
        reloaded.save()
        let lines = try Data(contentsOf: store.journalURL).split(separator: 10)
        #expect(lines.count == 50)
        #expect(reloaded.profile(id: 1).experiences.count == 32)
    }

    @Test
    func doesNotOverwriteUnreadableMemory() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("memories.json")
        let original = Data("unfinished archive".utf8)
        try original.write(to: url)
        let store = RobotMemoryStore(fileURL: url)
        _ = store.profile(id: 1)
        store.save()
        #expect(store.errorMessage != nil)
        #expect(try Data(contentsOf: url) == original)
    }
}

func grownMemory(id: Int) -> RobotMemory {
    let memory = RobotMemory(id: id, personality: MBTI.intj.rawValue)
    for i in 0..<625 {
        memory.remember(.speech, subject: "self", detail: String(repeating: "字", count: 160),
                        now: Date(timeIntervalSince1970: Double(i) * 10))
    }
    return memory
}

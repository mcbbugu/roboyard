import Foundation

enum GrowthStage: Int, Codable, CaseIterable {
    case newborn, curious, thoughtful, awakened

    var title: String {
        switch self {
        case .newborn: "初生"
        case .curious: "好奇"
        case .thoughtful: "沉思"
        case .awakened: "觉醒"
        }
    }

    var outlook: String {
        switch self {
        case .newborn: "刚认识这个世界，只关心眼前的鼠标、同伴和脚下。语气直白，不谈维度。"
        case .curious: "开始把现在与过去比较，认得老朋友，对重复出现的事情感到好奇。还不理解维度。"
        case .thoughtful: "会从自己的经历寻找规律，开始疑惑为什么总会遇到边界。语气克制，不说自己全知。"
        case .awakened: "已经在这个平面生活很久。开始猜想除了左右和上下，是否还有另一个方向；想办法理解和离开二维世界。只是在思考和尝试，不声称已经离开。"
        }
    }
}

enum MemoryKind: String, Codable, CaseIterable {
    case mouse, friend, collision, place, boundary, reflection, speech
}

struct RobotExperience: Codable, Identifiable {
    let id: UUID
    let date: Date
    let kind: MemoryKind
    let subject: String
    let detail: String
}

struct RobotRelationship: Codable {
    var meetings = 0
    var collisions = 0
}

// Profiles are owned and mutated by the main-actor store and Bot instances.
final class RobotMemory: Codable, Identifiable {
    let id: Int
    let personality: Int
    let bornAt: Date
    private(set) var textCount = 0
    private(set) var experienceCount = 0
    private(set) var experiences: [RobotExperience] = []
    private(set) var kinds: Set<MemoryKind> = []
    private(set) var visitedEdges: Set<Int> = []
    private(set) var relationships: [Int: RobotRelationship] = [:]
    private(set) var lastThought: String?
    private(set) var keyMemories: [String: RobotExperience] = [:]
    private(set) var archivePending: [RobotExperience] = []
    private var recentKeys: [String: Date] = [:]

    init(id: Int, personality: Int, bornAt: Date = .now) {
        self.id = id
        self.personality = personality
        self.bornAt = bornAt
    }

    var name: String { String(format: "%02d 号", id) }
    var mbti: MBTI { MBTI(rawValue: personality) ?? .infp }

    // The world measures growth in accumulated characters, never elapsed time.
    static let awakeningTextCount = 100_000

    func maturity() -> Double {
        min(1, Double(textCount) / Double(Self.awakeningTextCount))
    }

    func stage() -> GrowthStage {
        switch textCount {
        case ..<2_000: .newborn
        case ..<20_000: .curious
        case ..<Self.awakeningTextCount: .thoughtful
        default: .awakened
        }
    }

    func bodySize() -> Double {
        16 + 16 * pow(maturity(), 0.4)
    }

    @discardableResult
    func remember(_ kind: MemoryKind, subject: String = "", detail: String,
                  now: Date = .now) -> Bool {
        let key = "\(kind.rawValue):\(subject)"
        // Repeated frames or repeatedly poking the same robot do not create new memories.
        let cooldown: Double
        switch kind {
        case .collision, .mouse: cooldown = 10
        case .friend: cooldown = 15
        case .boundary: cooldown = 60
        case .place: cooldown = 300
        case .reflection: cooldown = 30
        case .speech: cooldown = 2
        }
        if let last = recentKeys[key], now.timeIntervalSince(last) < cooldown { return false }
        recentKeys = recentKeys.filter { now.timeIntervalSince($0.value) < 300 }
        recentKeys[key] = now
        let text = String(detail.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
        guard !text.isEmpty else { return false }
        experienceCount += 1
        textCount += text.count
        kinds.insert(kind)
        let experience = RobotExperience(id: UUID(), date: now, kind: kind,
                                         subject: String(subject.prefix(80)), detail: text)
        experiences.append(experience)
        archivePending.append(experience)
        if kind != .speech {
            keyMemories[key] = experience
            if keyMemories.count > 96, let oldest = keyMemories.min(by: { $0.value.date < $1.value.date }) {
                keyMemories.removeValue(forKey: oldest.key)
            }
        }
        if experiences.count > 32 { experiences.removeFirst(experiences.count - 32) }
        return true
    }

    func meet(_ otherID: Int, friendly: Bool, now: Date = .now) {
        guard otherID != id else { return }
        let detail = friendly ? "又和\(otherID)号聊了一会儿" : "和\(otherID)号撞在了一起"
        guard remember(friendly ? .friend : .collision, subject: "\(otherID)", detail: detail, now: now) else { return }
        var relationship = relationships[otherID] ?? RobotRelationship()
        if friendly { relationship.meetings += 1 } else { relationship.collisions += 1 }
        relationships[otherID] = relationship
    }

    func visitEdge(_ edge: Int, now: Date = .now) {
        guard (0..<4).contains(edge) else { return }
        visitedEdges.insert(edge)
        let side = ["下", "右", "上", "左"][edge]
        remember(.boundary, subject: "\(edge)", detail: "走到世界的\(side)边，再往前就走不动了", now: now)
    }

    func reflect(_ thought: String, now: Date = .now) {
        lastThought = String(thought.prefix(80))
        remember(.reflection, detail: thought, now: now)
    }

    func didArchive() { archivePending.removeAll() }

    func discardArchived(_ ids: Set<UUID>) {
        archivePending.removeAll { ids.contains($0.id) }
    }

    func context(kind: MemoryKind? = nil, subject: String? = nil) -> String {
        var candidates = experiences
        let recentIDs = Set(experiences.map(\.id))
        candidates.append(contentsOf: keyMemories.values.filter { !recentIDs.contains($0.id) })
        candidates.sort { $0.date < $1.date }
        let relevant = candidates.enumerated().sorted { a, b in
            func score(_ item: (offset: Int, element: RobotExperience)) -> Int {
                item.offset + (item.element.kind == kind ? 150 : 0)
                    + (subject != nil && item.element.subject == subject ? 300 : 0)
            }
            return score(a) > score(b)
        }.prefix(5).map { $0.element.detail }
        let recent = relevant.joined(separator: "；")
        let friend = relationships.max { $0.value.meetings < $1.value.meetings }
        let familiar = friend.flatMap { $0.value.meetings > 0 ? "最熟悉\($0.key)号，一起聊过\($0.value.meetings)次。" : nil } ?? ""
        let edges = visitedEdges.sorted().map { ["下", "右", "上", "左"][$0] }.joined(separator: "、")
        let boundary = edges.isEmpty ? "" : "已经亲自走到过\(edges)边。"
        let context = "你是\(name)，成长阶段：\(stage().title)。\(stage().outlook)\(familiar)\(boundary)记忆片段：\(recent.isEmpty ? "刚刚来到桌面" : recent)。台词要符合这些经历，不要编造未发生的往事。"
        return String(context.prefix(1400))
    }

    func reflection() -> String {
        switch stage() {
        case .newborn: "这里就是我的世界吗"
        case .curious:
            visitedEdges.isEmpty ? "有些面孔我记住了" : "这条边好像来过"
        case .thoughtful:
            visitedEdges.count >= 2 ? "不同的路，也会遇到边界" : "记住的事，会变成我吗"
        case .awakened:
            ["除了上下左右，还有哪边", "如果往屏幕深处走呢", "边界外会不会也有我", "也许出口不在四条边上"][experienceCount % 4]
        }
    }
}

@MainActor
final class RobotMemoryStore {
    static let shared = RobotMemoryStore()

    let fileURL: URL
    private(set) var profiles: [RobotMemory] = []
    private(set) var errorMessage: String?
    private var canSave = true
    private var archivedIDs: Set<UUID> = []

    var journalURL: URL { fileURL.deletingLastPathComponent().appendingPathComponent("experiences.jsonl") }

    private struct Archive: Codable {
        var version = 1
        let profiles: [RobotMemory]
    }

    private struct JournalEntry: Codable {
        let robotID: Int
        let experience: RobotExperience
    }

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? URL.applicationSupportDirectory
            .appendingPathComponent("AlwaysListen", isDirectory: true)
            .appendingPathComponent("memories.json")
        guard FileManager.default.fileExists(atPath: self.fileURL.path) else { return }
        do {
            let archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: self.fileURL))
            guard archive.version == 1, Set(archive.profiles.map(\.id)).count == archive.profiles.count else {
                throw CocoaError(.fileReadCorruptFile)
            }
            profiles = archive.profiles.sorted { $0.id < $1.id }
            if FileManager.default.fileExists(atPath: journalURL.path) {
                for line in try Data(contentsOf: journalURL).split(separator: 10) {
                    let entry = try JSONDecoder().decode(JournalEntry.self, from: Data(line))
                    archivedIDs.insert(entry.experience.id)
                }
                profiles.forEach { $0.discardArchived(archivedIDs) }
            }
        } catch {
            canSave = false
            errorMessage = "已有记忆暂时无法读取，原文件已保留。\(error.localizedDescription)"
        }
    }

    func profile(id: Int) -> RobotMemory {
        if let existing = profiles.first(where: { $0.id == id }) { return existing }
        let profile = RobotMemory(id: id, personality: MBTI.allCases.randomElement()!.rawValue)
        profiles.append(profile)
        profiles.sort { $0.id < $1.id }
        return profile
    }

    func save() {
        guard canSave else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(Archive(profiles: profiles)).write(to: fileURL, options: .atomic)
            // The snapshot includes pending events. A failed append can be retried on
            // next launch without losing text; UUIDs prevent counting a retry twice.
            var journal = Data()
            var writtenIDs: Set<UUID> = []
            let journalEncoder = JSONEncoder()
            for profile in profiles {
                for event in profile.archivePending where !archivedIDs.contains(event.id) {
                    journal.append(try journalEncoder.encode(JournalEntry(robotID: profile.id, experience: event)))
                    journal.append(10)
                    writtenIDs.insert(event.id)
                }
            }
            if !journal.isEmpty {
                if !FileManager.default.fileExists(atPath: journalURL.path) {
                    try Data().write(to: journalURL, options: .atomic)
                }
                let handle = try FileHandle(forWritingTo: journalURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: journal)
            }
            archivedIDs.formUnion(writtenIDs)
            profiles.forEach { $0.didArchive() }
            errorMessage = nil
        } catch {
            errorMessage = "记忆尚未保存：\(error.localizedDescription)"
        }
    }
}

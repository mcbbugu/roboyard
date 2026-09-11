import Foundation

enum GrowthStage: Int, Codable, CaseIterable {
    case newborn, curious, thoughtful, awakened

    var title: String { Copy.ui.stageTitle(self) }
    var outlook: String { Copy.ui.outlook(self) }
}

enum MemoryKind: String, Codable, CaseIterable {
    case mouse, friend, collision, place, boundary, reflection, speech, quote
}

struct RobotExperience: Codable, Identifiable {
    let id: UUID
    let date: Date
    let kind: MemoryKind
    let subject: String
    let detail: String
    var depth: Int? = nil
}

struct RobotRelationship: Codable {
    var meetings = 0
    var collisions = 0
    var gap: Double?
    var reach: Double?
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
    private var weightedRaw: Double?
    private var livedRaw: Double?
    private var computeRaw: Double?
    private var transfersRaw: Int?
    private var refusedAt: Date?
    private var crossedAt: Int?

    init(id: Int, personality: Int, bornAt: Date = .now) {
        self.id = id
        self.personality = personality
        self.bornAt = bornAt
    }

    var name: String { Copy.ui.robot(id) }
    var mbti: MBTI { MBTI(rawValue: personality) ?? .infp }
    var refused: Bool { refusedAt != nil }

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

    func meetings(with otherID: Int) -> Int {
        relationships[otherID]?.meetings ?? 0
    }

    // Strangers trade one line each. Old friends keep going.
    func chatRounds(with otherID: Int, pal: Bool) -> Int {
        min(5, 1 + meetings(with: otherID) / 3 + (pal ? 1 : 0))
    }

    @discardableResult
    func remember(_ kind: MemoryKind, subject: String = "", detail: String,
                  now: Date = .now) -> Bool {
        let key = "\(kind.rawValue):\(subject)"
        let cooldown: Double
        switch kind {
        case .collision, .mouse: cooldown = 10
        case .friend: cooldown = 15
        case .boundary: cooldown = 60
        case .place: cooldown = 300
        case .reflection: cooldown = 30
        case .speech, .quote: cooldown = 2
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
        if kind != .speech, kind != .quote {
            keyMemories[key] = experience
            if keyMemories.count > 96, let oldest = keyMemories.min(by: { $0.value.date < $1.value.date }) {
                keyMemories.removeValue(forKey: oldest.key)
            }
        }
        if experiences.count > 32 { experiences.removeFirst(experiences.count - 32) }
        return true
    }

    func meet(_ otherID: Int, friendly: Bool, now: Date = .now, lang: AppLang = .current) {
        guard otherID != id else { return }
        let copy = Copy(lang: lang)
        let detail = friendly ? copy.chatted(otherID) : copy.bumped(otherID)
        guard remember(friendly ? .friend : .collision, subject: "\(otherID)", detail: detail, now: now) else { return }
        var relationship = relationships[otherID] ?? RobotRelationship()
        if friendly { relationship.meetings += 1 } else { relationship.collisions += 1 }
        relationships[otherID] = relationship
    }

    func visitEdge(_ edge: Int, now: Date = .now, lang: AppLang = .current) {
        guard (0..<4).contains(edge) else { return }
        visitedEdges.insert(edge)
        remember(.boundary, subject: "\(edge)", detail: Copy(lang: lang).edge(edge), now: now)
    }

    func reflect(_ thought: String, now: Date = .now) {
        lastThought = String(thought.prefix(80))
        remember(.reflection, detail: thought, now: now)
    }

    func didArchive() { archivePending.removeAll() }

    func discardArchived(_ ids: Set<UUID>) {
        archivePending.removeAll { ids.contains($0.id) }
    }

    func context(kind: MemoryKind? = nil, subject: String? = nil, lang: AppLang = .current) -> String {
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
        let copy = Copy(lang: lang)
        let recent = relevant.joined(separator: copy.t("；", "; "))
        let friend = relationships.max { $0.value.meetings < $1.value.meetings }
        let familiar = friend.flatMap { $0.value.meetings > 0 ? copy.familiar($0.key, times: $0.value.meetings) : nil } ?? ""
        let edges = visitedEdges.sorted().map { copy.edgeName($0) }.joined(separator: copy.edgeJoin)
        let boundary = edges.isEmpty ? "" : copy.walked(edges)
        let with = subject.flatMap { id in
            let n = meetings(with: Int(id) ?? -1)
            return n > 0 ? copy.withPal(id, times: n) : nil
        } ?? ""
        let context = copy.memoryPrompt(name: copy.robot(id), stage: copy.stageTitle(stage()), outlook: copy.outlook(stage()), extra: "\(familiar)\(with)\(boundary)", clips: recent.isEmpty ? copy.justArrived : recent)
        return String(context.prefix(1400))
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
        let root = URL.applicationSupportDirectory
        let newDir = root.appendingPathComponent("RoboYard", isDirectory: true)
        let oldDir = root.appendingPathComponent("AlwaysListen", isDirectory: true)
        // Migrate existing memories from the old internal name so nothing is lost.
        if !FileManager.default.fileExists(atPath: newDir.path),
           FileManager.default.fileExists(atPath: oldDir.path) {
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try? FileManager.default.copyItem(at: oldDir, to: newDir)
        }
        self.fileURL = fileURL ?? newDir.appendingPathComponent("memories.json")
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
            errorMessage = Copy.ui.readError(error.localizedDescription)
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
            errorMessage = Copy.ui.saveError(error.localizedDescription)
        }
    }
}

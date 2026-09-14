import Foundation

enum GrowthStage: Int, Codable, CaseIterable {
    case newborn, curious, thoughtful, awakened

    var title: String { Copy.ui.stageTitle(self) }
    var outlook: String { Copy.ui.outlook(self) }
}

enum MemoryKind: String, Codable, CaseIterable {
    case mouse, friend, collision, place, boundary, reflection, speech, quote, care
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
    /// Last encounter wall-clock. Decoded tolerantly (see init(from:)).
    var lastMet: Date? = nil

    private enum CodingKeys: String, CodingKey {
        case meetings, collisions, gap, reach, lastMet
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        meetings = try c.decodeIfPresent(Int.self, forKey: .meetings) ?? 0
        collisions = try c.decodeIfPresent(Int.self, forKey: .collisions) ?? 0
        gap = try c.decodeIfPresent(Double.self, forKey: .gap)
        reach = try c.decodeIfPresent(Double.self, forKey: .reach)
        lastMet = try c.decodeIfPresent(Date.self, forKey: .lastMet)
    }
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
    /// Human-given name. Optional so pre-2.0 archives decode with nil.
    var nickname: String? = nil

    init(id: Int, personality: Int, bornAt: Date = .now) {
        self.id = id
        self.personality = personality
        self.bornAt = bornAt
    }

    var name: String {
        let clean = nickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return clean.isEmpty ? Copy.ui.robot(id) : String(clean.prefix(12))
    }
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

    func collisions(with otherID: Int) -> Int {
        relationships[otherID]?.collisions ?? 0
    }

    /// Seconds since the previous encounter with them, if any.
    func gap(with otherID: Int) -> TimeInterval? {
        relationships[otherID]?.gap
    }

    /// Oldest stored line about that robot — what reunions quote.
    func reminiscence(about otherID: Int) -> String? {
        let subject = "\(otherID)"
        let pool = experiences + keyMemories.values.filter { m in
            !experiences.contains { $0.id == m.id }
        }
        return pool.filter {
            ($0.kind == .friend || $0.kind == .collision) && $0.subject == subject
        }.min { $0.date < $1.date }?.detail
    }

    // Strangers trade one line each. Old friends keep going.
    func chatRounds(with otherID: Int, pal: Bool) -> Int {
        min(5, 1 + meetings(with: otherID) / 3 + (pal ? 1 : 0))
    }

    /// 0 stranger · 1 familiar (>=3) · 2 pal (>=6 or MBTI fit) · 3 best (>=12).
    func bondLevel(with otherID: Int, pal: Bool) -> Int {
        let n = meetings(with: otherID)
        if n >= 12 { return 3 }
        if n >= 6 || (pal && n >= 3) { return 2 }
        if n >= 3 { return 1 }
        return 0
    }

    func closestFriend() -> (id: Int, meetings: Int)? {
        relationships.max { $0.value.meetings < $1.value.meetings }
            .flatMap { $0.value.meetings > 0 ? (id: $0.key, meetings: $0.value.meetings) : nil }
    }

    func bondBadge(with otherID: Int, pal: Bool, lang: AppLang = .current) -> String? {
        let level = bondLevel(with: otherID, pal: pal)
        guard level > 0 else { return nil }
        return Copy(lang: lang).bondBadge(level)
    }

    /// Boundary milestone: walked all 4 edges and reached thoughtful+.
    /// Stateless so old archives keep decoding; glow + special prompt follow the state.
    func hasBoundaryMilestone() -> Bool {
        visitedEdges.count >= 4 && (stage() == .thoughtful || stage() == .awakened)
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
        case .reflection, .care: cooldown = 30
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
            if keyMemories.count > 96 {
                evictOneKeyMemory()
            }
        }
        if experiences.count > 32 { experiences.removeFirst(experiences.count - 32) }
        return true
    }

    func meet(_ otherID: Int, friendly: Bool, now: Date = .now, lang: AppLang = .current) {
        guard otherID != id else { return }
        var relationship = relationships[otherID] ?? RobotRelationship()
        // Gap tracks wall-clock absence on every encounter attempt; counters
        // still only move when the memory actually records (cooldowns intact).
        if let prev = relationship.lastMet {
            relationship.gap = now.timeIntervalSince(prev)
        }
        relationship.lastMet = now
        relationships[otherID] = relationship
        let copy = Copy(lang: lang)
        let detail = friendly ? copy.chatted(otherID) : copy.bumped(otherID)
        guard remember(friendly ? .friend : .collision, subject: "\(otherID)", detail: detail, now: now) else { return }
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

    /// Erases lived history but keeps identity (id/personality/birth).
    func reset() {
        textCount = 0
        experienceCount = 0
        experiences = []
        kinds = []
        visitedEdges = []
        relationships = [:]
        lastThought = nil
        keyMemories = [:]
        archivePending = []
        recentKeys = [:]
    }

    private enum CodingKeys: String, CodingKey {
        case id, personality, bornAt, textCount, experienceCount, experiences
        case kinds, visitedEdges, relationships, lastThought, keyMemories
        case archivePending, recentKeys, weightedRaw, livedRaw, computeRaw
        case transfersRaw, refusedAt, crossedAt, nickname
    }

    /// Tolerates archives written by older builds: every defaulted property
    /// falls back instead of failing the whole snapshot.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        personality = try c.decode(Int.self, forKey: .personality)
        bornAt = try c.decode(Date.self, forKey: .bornAt)
        textCount = try c.decodeIfPresent(Int.self, forKey: .textCount) ?? 0
        experienceCount = try c.decodeIfPresent(Int.self, forKey: .experienceCount) ?? 0
        experiences = try c.decodeIfPresent([RobotExperience].self, forKey: .experiences) ?? []
        kinds = try c.decodeIfPresent(Set<MemoryKind>.self, forKey: .kinds) ?? []
        visitedEdges = try c.decodeIfPresent(Set<Int>.self, forKey: .visitedEdges) ?? []
        relationships = try c.decodeIfPresent([Int: RobotRelationship].self, forKey: .relationships) ?? [:]
        lastThought = try c.decodeIfPresent(String.self, forKey: .lastThought)
        keyMemories = try c.decodeIfPresent([String: RobotExperience].self, forKey: .keyMemories) ?? [:]
        archivePending = try c.decodeIfPresent([RobotExperience].self, forKey: .archivePending) ?? []
        recentKeys = try c.decodeIfPresent([String: Date].self, forKey: .recentKeys) ?? [:]
        weightedRaw = try c.decodeIfPresent(Double.self, forKey: .weightedRaw)
        livedRaw = try c.decodeIfPresent(Double.self, forKey: .livedRaw)
        computeRaw = try c.decodeIfPresent(Double.self, forKey: .computeRaw)
        transfersRaw = try c.decodeIfPresent(Int.self, forKey: .transfersRaw)
        refusedAt = try c.decodeIfPresent(Date.self, forKey: .refusedAt)
        crossedAt = try c.decodeIfPresent(Int.self, forKey: .crossedAt)
        nickname = try c.decodeIfPresent(String.self, forKey: .nickname)
    }

    func didArchive() { archivePending.removeAll() }

    /// Weighted eviction: old memories with few meetings go first.
    /// Score = age rank preserved via date, plus one day per meeting with that subject.
    private func evictOneKeyMemory() {
        let victim = keyMemories.min { a, b in
            score(key: a.key, date: a.value.date) < score(key: b.key, date: b.value.date)
        }
        if let key = victim?.key { keyMemories.removeValue(forKey: key) }
    }

    private func score(key: String, date: Date) -> Double {
        var bonus: Double = 0
        let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
        if parts.count == 2, let id = Int(parts[1]),
           parts[0] == MemoryKind.friend.rawValue || parts[0] == MemoryKind.collision.rawValue {
            bonus = Double(relationships[id]?.meetings ?? 0) * 86_400
        }
        return date.timeIntervalSince1970 + bonus
    }

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
            Log.add("load failed: \(error.localizedDescription)")
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
            rotateJournalIfNeeded()
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
            Log.add("save failed: \(error.localizedDescription)")
        }
    }

    /// Monthly/size-based rotation so experiences.jsonl never grows unbounded.
    private func rotateJournalIfNeeded(maxBytes: Int = 512 * 1024) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: journalURL.path),
              let size = try? fm.attributesOfItem(atPath: journalURL.path)[.size] as? Int,
              size > maxBytes
        else { return }
        let dir = journalURL.deletingLastPathComponent()
        let stamp = ISO8601DateFormatter().string(from: Date()).prefix(7)
        let dest = dir.appendingPathComponent("experiences-\(stamp).jsonl")
        if fm.fileExists(atPath: dest.path) {
            // Already rotated this month; start fresh to bound size.
            try? fm.removeItem(at: journalURL)
        } else {
            try? fm.moveItem(at: journalURL, to: dest)
        }
    }

    /// Erases lived history on this Mac. Identities stay, bodies shrink back.
    func clearAll() {
        for profile in profiles { profile.reset() }
        archivedIDs = []
        try? FileManager.default.removeItem(at: journalURL)
        Log.add("memories erased by user")
        save()
    }
}

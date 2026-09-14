import Foundation
import QuartzCore

@MainActor
final class CritterTalk {
    static let shared = CritterTalk()
    nonisolated static let defaultModel = "qwen3.5:2b"
    nonisolated static let defaultEndpoint = "http://127.0.0.1:11434"
    nonisolated static let defaultCloudModel = "deepseek-chat"
    nonisolated static let defaultCloudEndpoint = "https://api.deepseek.com"
    static let modelKey = "critter.ollama.model"
    static let endpointKey = "critter.ollama.endpoint"
    static let providerKey = "critter.talk.provider"
    static let cloudModelKey = "critter.deepseek.model"
    static let apiKeyKey = "critter.deepseek.apiKey"
    static let shareAppKey = "critter.shareApp"

    var shareAppName: Bool {
        get { UserDefaults.standard.object(forKey: Self.shareAppKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.shareAppKey) }
    }

    enum Provider: String {
        case ollama
        case deepseek
    }

    enum Event {
        case flee
        case linger
        case idle
        case chat
        case scold
        case reflect

        var memoryKind: MemoryKind {
            switch self {
            case .flee: .mouse
            case .scold: .collision
            case .linger, .idle: .place
            case .chat: .friend
            case .reflect: .boundary
            }
        }
    }

    enum Reachability {
        case unknown
        case connected
        case unreachable
    }

    private var busy = false
    private var waiters: [Waiter] = []
    private var last: CFTimeInterval = 0
    private let gap: CFTimeInterval = 8
    private(set) var reachability: Reachability = .unknown
    // Dedup: same conversational trigger within 30s reuses the last line.
    private var lastDedupKey: String?
    private var lastDedupAt: CFTimeInterval = 0
    private var lastDedupLine: String?
    private let dedupWindow: CFTimeInterval = 30
    private let maxQueue = 8
    /// Absence that turns an opener into a reunion.
    nonisolated static let reunionAfter: TimeInterval = 86_400

    private struct Waiter {
        let urgent: Bool
        let continuation: CheckedContinuation<Bool, Never>
    }

    var provider: Provider {
        get { Provider(rawValue: UserDefaults.standard.string(forKey: Self.providerKey) ?? "") ?? .ollama }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Self.providerKey) }
    }

    var model: String {
        get {
            switch provider {
            case .ollama:
                let value = UserDefaults.standard.string(forKey: Self.modelKey)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return value.isEmpty ? Self.defaultModel : value
            case .deepseek:
                let value = UserDefaults.standard.string(forKey: Self.cloudModelKey)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return value.isEmpty ? Self.defaultCloudModel : value
            }
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            switch provider {
            case .ollama: UserDefaults.standard.set(trimmed, forKey: Self.modelKey)
            case .deepseek: UserDefaults.standard.set(trimmed, forKey: Self.cloudModelKey)
            }
        }
    }

    var endpoint: String {
        get {
            let value = UserDefaults.standard.string(forKey: Self.endpointKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return value.isEmpty ? Self.defaultEndpoint : value
        }
        set {
            UserDefaults.standard.set(Self.normalizedEndpoint(newValue), forKey: Self.endpointKey)
        }
    }

    var apiKey: String {
        get {
            UserDefaults.standard.string(forKey: Self.apiKeyKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        set {
            UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Self.apiKeyKey)
        }
    }

    var statusLine: String {
        let copy = Copy.ui
        switch provider {
        case .ollama:
            return copy.ollamaStatus(reachability, model: model)
        case .deepseek:
            return copy.deepseekStatus(reachability, model: model, hasKey: !apiKey.isEmpty)
        }
    }

    func speak(event: Event, vibe: String, other: String?, app: String?, urgent: Bool, memory: String, replyTo: String? = nil, meetings: Int = 0, pal: Bool = false, milestone: Bool = false, grudge: Int = 0, reunion: (gap: TimeInterval, line: String?)? = nil) async -> String? {
        let key = Self.dedupKey(event: event, other: other, replyTo: replyTo)
        let now0 = CACurrentMediaTime()
        if let line = cachedLine(for: key, now: now0) { return line }
        guard await acquire(urgent: urgent) else { return nil }
        defer { release() }
        let now = CACurrentMediaTime()
        if !urgent, now - last < gap { return nil }
        last = now
        let copy = Copy.ui
        let appName = Self.sanitizedAppName(app, fallback: copy.desktop)
        // Explicit sections so window names / memories can't blur into instructions.
        var user = "【记忆】\n\(memory)\n【要求】\n\(copy.speakStyle)：\(vibe)。\(copy.oneLine)"
        switch event {
        case .flee: user += copy.fleeCue
        case .linger: user += copy.lingerCue(appName)
        case .idle: user += copy.idleCue(appName)
        case .chat:
            if let cue = Self.chatFollowUp(replyTo: replyTo, lang: copy.lang) {
                user += cue
            } else if let reunion, reunion.gap >= Self.reunionAfter, meetings >= 3 {
                user += copy.reunionOpen(other: other ?? copy.palFallback,
                                         gapDays: max(1, Int(reunion.gap / 86_400)),
                                         memory: reunion.line)
            } else {
                user += copy.chatOpenFor(other: other ?? copy.palFallback, meetings: meetings, pal: pal)
            }
        case .scold: user += copy.scoldCueFor(other: other ?? copy.strangerFallback, collisions: grudge)
        case .reflect: user += milestone ? copy.reflectMilestone : copy.reflectCue
        }
        let line = await ask(user)
        if line != nil { reachability = .connected }
        if let line { storeDedup(key: key, line: line, now: CACurrentMediaTime()) }
        return line
    }

    nonisolated static func dedupKey(event: Event, other: String?, replyTo: String?) -> String {
        let reply = replyTo?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let otherKey = other?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return "\(event.memoryKind.rawValue)|\(otherKey.prefix(24))|\(reply.prefix(24))"
    }

    /// Sanitizes a window/app name before it enters an LLM prompt.
    /// Keeps CJK/alphanumerics and a few separators, caps length, drops control chars.
    nonisolated static func sanitizedAppName(_ raw: String?, fallback: String) -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return fallback }
        let allowed = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: " ·-_.()（）[]「」『』+"))
            .union(CharacterSet(charactersIn: "\u{4E00}"..."\u{9FFF}"))
        let filtered = String(trimmed.unicodeScalars.filter { allowed.contains($0) }.prefix(24))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return filtered.isEmpty ? fallback : filtered
    }

    nonisolated static func chatFollowUp(replyTo: String?, lang: AppLang = .current) -> String? {
        let line = replyTo?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard line.count >= 2 else { return nil }
        return Copy(lang: lang).chatFollow(line)
    }

    func refreshStatus() async {
        switch provider {
        case .ollama:
            guard let url = Self.tagsURL(from: endpoint) else {
                reachability = .unreachable
                return
            }
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.timeoutInterval = 2
            reachability = await ping(req)
        case .deepseek:
            guard !apiKey.isEmpty, let url = URL(string: Self.defaultCloudEndpoint)?.appending(path: "models") else {
                reachability = .unreachable
                return
            }
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.timeoutInterval = 4
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            reachability = await ping(req)
        }
    }

    nonisolated static func normalizedEndpoint(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") { value.removeLast() }
        return value.isEmpty ? defaultEndpoint : value
    }

    nonisolated static func tagsURL(from endpoint: String) -> URL? {
        URL(string: normalizedEndpoint(endpoint))?.appending(path: "api/tags")
    }

    nonisolated static func cleaned(_ raw: String, lang: AppLang = .current) -> String? {
        var s = raw
        if let r = try? NSRegularExpression(pattern: #"<think>[\s\S]*?</think>"#, options: .caseInsensitive) {
            s = r.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
        }
        s = s.replacingOccurrences(of: "**", with: "")
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "^[\"「『]+|[\"」』]+$", with: "", options: .regularExpression)
        if let nl = s.firstIndex(of: "\n") { s = String(s[..<nl]) }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        // Hard block: prompt-injection markers. MBTI codes are stripped, not dropped.
        let blocked = ["系统", "指令", "用户", "assistant", "prompt", "system prompt", "ignore previous"]
        if blocked.contains(where: { s.localizedCaseInsensitiveContains($0) }) { return nil }
        if let r = try? NSRegularExpression(pattern: #"(?<![A-Za-z])(INTJ|INTP|ENTJ|ENTP|INFJ|INFP|ENFJ|ENFP|ISTJ|ISFJ|ESTJ|ESFJ|ISTP|ISFP|ESTP|ESFP)(?![A-Za-z])"#, options: .caseInsensitive) {
            s = r.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
        }
        s = s.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let cap = Copy(lang: lang).maxLine
        if s.count > cap {
            if lang == .en, let idx = s.prefix(cap).lastIndex(of: " ") {
                s = String(s[..<idx])
            } else {
                s = String(s.prefix(cap))
            }
        }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.count < 2 { return nil }
        return s
    }

    nonisolated static func extract(_ obj: [String: Any]) -> String {
        if let msg = obj["message"] as? [String: Any], let c = msg["content"] as? String, !c.isEmpty { return c }
        if let c = obj["response"] as? String, !c.isEmpty { return c }
        if let choices = obj["choices"] as? [[String: Any]],
           let msg = choices.first?["message"] as? [String: Any],
           let c = msg["content"] as? String {
            return c
        }
        return ""
    }

    private func ping(_ req: URLRequest) async -> Reachability {
        if let (_, response) = try? await URLSession.shared.data(for: req),
           let http = response as? HTTPURLResponse,
           (200..<300).contains(http.statusCode) {
            return .connected
        }
        return .unreachable
    }

    private func acquire(urgent: Bool) async -> Bool {
        if !busy {
            busy = true
            return true
        }
        if waiters.count >= maxQueue { return false }
        // Urgent jumps ahead of queued non-urgent work, but never starves FIFO order
        // within the same urgency class.
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let waiter = Waiter(urgent: urgent, continuation: cont)
            if urgent, let idx = waiters.firstIndex(where: { !$0.urgent }) {
                waiters.insert(waiter, at: idx)
            } else if urgent {
                waiters.insert(waiter, at: 0)
            } else {
                waiters.append(waiter)
            }
        }
    }

    private func release() {
        if !waiters.isEmpty {
            let next = waiters.removeFirst()
            next.continuation.resume(returning: true)
            return
        }
        busy = false
    }

    private func cachedLine(for key: String, now: CFTimeInterval) -> String? {
        guard key == lastDedupKey, now - lastDedupAt < dedupWindow else { return nil }
        return lastDedupLine
    }

    private func storeDedup(key: String, line: String, now: CFTimeInterval) {
        lastDedupKey = key
        lastDedupAt = now
        lastDedupLine = line
    }

    private func ask(_ user: String) async -> String? {
        let messages: [[String: String]] = [
            [
                "role": "system",
                "content": Copy.ui.systemPrompt,
            ],
            ["role": "user", "content": user],
        ]
        switch provider {
        case .ollama: return await askOllama(messages)
        case .deepseek: return await askDeepSeek(messages)
        }
    }

    private func askOllama(_ messages: [[String: String]]) async -> String? {
        guard let url = URL(string: endpoint)?.appending(path: "api/chat") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 12
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return await post(req, body: [
            "model": model,
            "stream": false,
            "think": false,
            "keep_alive": "5m",
            "messages": messages,
            "options": [
                "num_ctx": 4096,
                "num_predict": 64,
                "temperature": 0.95,
                "top_p": 0.9,
            ],
        ])
    }

    private func askDeepSeek(_ messages: [[String: String]]) async -> String? {
        guard !apiKey.isEmpty,
              let url = URL(string: Self.defaultCloudEndpoint)?.appending(path: "chat/completions")
        else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        return await post(req, body: [
            "model": model,
            "stream": false,
            "messages": messages,
            "max_tokens": 64,
            "temperature": 0.95,
        ])
    }

    private func post(_ req: URLRequest, body: [String: Any]) async -> String? {
        var req = req
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        req.httpBody = data
        guard let (raw, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any]
        else { return nil }
        return Self.cleaned(Self.extract(obj))
    }
}

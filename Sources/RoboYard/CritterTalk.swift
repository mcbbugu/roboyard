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
    private var pendingUrgent: CheckedContinuation<Bool, Never>?
    private var last: CFTimeInterval = 0
    private let gap: CFTimeInterval = 8
    private(set) var reachability: Reachability = .unknown

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
        switch provider {
        case .ollama:
            switch reachability {
            case .unknown: return "Ollama · 未检测"
            case .connected: return "Ollama · \(model)"
            case .unreachable: return "Ollama · 未连接（沉默）"
            }
        case .deepseek:
            if apiKey.isEmpty { return "DeepSeek · 未填密钥" }
            switch reachability {
            case .unknown: return "DeepSeek · 未检测"
            case .connected: return "DeepSeek · \(model)"
            case .unreachable: return "DeepSeek · 未连接（沉默）"
            }
        }
    }

    func speak(event: Event, vibe: String, other: String?, app: String?, urgent: Bool, memory: String, replyTo: String? = nil) async -> String? {
        guard await acquire(urgent: urgent) else { return nil }
        defer { release() }
        let now = CACurrentMediaTime()
        if !urgent, now - last < gap { return nil }
        last = now
        let appName = (app?.isEmpty == false) ? app! : "桌面"
        var user = "\(memory)\n说话风格：\(vibe)。只说那一句台词。"
        switch event {
        case .flee: user += "鼠标贴过来了，边跑边喊。"
        case .linger: user += "人盯着\(appName)很久了。"
        case .idle: user += "停在原地歇着，眼前是\(appName)。"
        case .chat:
            if let cue = Self.chatFollowUp(replyTo: replyTo) {
                user += cue
            } else {
                user += "你开口跟眼前的同伴说话。对方风格：\(other ?? "同类")。抛一句对方接得上的话。"
            }
        case .scold: user += "被撞了，正追着对方骂。对方风格：\(other ?? "路人")。"
        case .reflect: user += "安静下来，回想一件亲历的事，说出此刻冒出的一个疑问。让思考符合你的成长阶段。"
        }
        let line = await ask(user)
        if line != nil { reachability = .connected }
        return line
    }

    nonisolated static func chatFollowUp(replyTo: String?) -> String? {
        let line = replyTo?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard line.count >= 2 else { return nil }
        return "你在和同伴对话。对方刚说：\(line)。必须接这一句，问答、顺着说或轻轻反驳都行，不要另起一个无关话题。"
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

    nonisolated static func cleaned(_ raw: String) -> String? {
        var s = raw
        if let r = try? NSRegularExpression(pattern: #"<think>[\s\S]*?</think>"#, options: .caseInsensitive) {
            s = r.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
        }
        s = s.replacingOccurrences(of: "**", with: "")
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "^[\"「『]+|[\"」』]+$", with: "", options: .regularExpression)
        if let nl = s.firstIndex(of: "\n") { s = String(s[..<nl]) }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let banned = ["系统", "指令", "用户", "assistant", "prompt", "INTJ", "INTP", "ENTJ", "ENTP", "INFJ", "INFP", "ENFJ", "ENFP", "ISTJ", "ISFJ", "ESTJ", "ESFJ", "ISTP", "ISFP", "ESTP", "ESFP"]
        if banned.contains(where: { s.localizedCaseInsensitiveContains($0) }) { return nil }
        if s.count > 18 { s = String(s.prefix(18)) }
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
        if !urgent { return false }
        if let old = pendingUrgent {
            pendingUrgent = nil
            old.resume(returning: false)
        }
        return await withCheckedContinuation { pendingUrgent = $0 }
    }

    private func release() {
        if let next = pendingUrgent {
            pendingUrgent = nil
            next.resume(returning: true)
            return
        }
        busy = false
    }

    private func ask(_ user: String) async -> String? {
        let messages: [[String: String]] = [
            [
                "role": "system",
                "content": "小四足机器人。只回一句中文口语，最多14字。不要解释，不要引号，不要写出编号或性格类型。",
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
        guard let (raw, _) = try? await URLSession.shared.data(for: req),
              let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any]
        else { return nil }
        return Self.cleaned(Self.extract(obj))
    }
}

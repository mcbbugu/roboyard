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
        let copy = Copy.ui
        switch provider {
        case .ollama:
            return copy.ollamaStatus(reachability, model: model)
        case .deepseek:
            return copy.deepseekStatus(reachability, model: model, hasKey: !apiKey.isEmpty)
        }
    }

    func speak(event: Event, vibe: String, other: String?, app: String?, urgent: Bool, memory: String, replyTo: String? = nil) async -> String? {
        guard await acquire(urgent: urgent) else { return nil }
        defer { release() }
        let now = CACurrentMediaTime()
        if !urgent, now - last < gap { return nil }
        last = now
        let copy = Copy.ui
        let appName = (app?.isEmpty == false) ? app! : copy.desktop
        var user = "\(memory)\n\(copy.speakStyle)：\(vibe)。\(copy.oneLine)"
        switch event {
        case .flee: user += copy.fleeCue
        case .linger: user += copy.lingerCue(appName)
        case .idle: user += copy.idleCue(appName)
        case .chat:
            if let cue = Self.chatFollowUp(replyTo: replyTo, lang: copy.lang) {
                user += cue
            } else {
                user += copy.chatOpen(other ?? copy.palFallback)
            }
        case .scold: user += copy.scoldCue(other ?? copy.strangerFallback)
        case .reflect: user += copy.reflectCue
        }
        let line = await ask(user)
        if line != nil { reachability = .connected }
        return line
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
        let banned = ["系统", "指令", "用户", "assistant", "prompt", "INTJ", "INTP", "ENTJ", "ENTP", "INFJ", "INFP", "ENFJ", "ENFP", "ISTJ", "ISFJ", "ESTJ", "ESFJ", "ISTP", "ISFP", "ESTP", "ESFP"]
        if banned.contains(where: { s.localizedCaseInsensitiveContains($0) }) { return nil }
        let cap = Copy(lang: lang).maxLine
        if s.count > cap { s = String(s.prefix(cap)) }
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
        guard let (raw, _) = try? await URLSession.shared.data(for: req),
              let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any]
        else { return nil }
        return Self.cleaned(Self.extract(obj))
    }
}

import Foundation
import QuartzCore

@MainActor
final class CritterTalk {
    static let shared = CritterTalk()
    static let model = "qwen3.5:2b"

    enum Event {
        case flee
        case bump
        case linger
        case idle
        case chat
        case scold
        case reflect

        var memoryKind: MemoryKind {
            switch self {
            case .flee: .mouse
            case .bump, .scold: .collision
            case .linger, .idle: .place
            case .chat: .friend
            case .reflect: .boundary
            }
        }
    }

    private var busy = false
    private var last: CFTimeInterval = 0
    private let gap: CFTimeInterval = 8

    var ready: Bool {
        !busy && CACurrentMediaTime() - last >= gap
    }

    func speak(event: Event, vibe: String, other: String?, app: String?, urgent: Bool, memory: String) async -> String? {
        if busy { return nil }
        let now = CACurrentMediaTime()
        if !urgent, now - last < gap { return nil }
        busy = true
        last = now
        defer { busy = false }
        let appName = (app?.isEmpty == false) ? app! : "桌面"
        var user = "\(memory)\n说话风格：\(vibe)。只说那一句台词。"
        switch event {
        case .flee: user += "鼠标贴过来了，边跑边喊。"
        case .bump: user += "被同伴撞了。"
        case .linger: user += "人盯着\(appName)很久了。"
        case .idle: user += "停在原地歇着，眼前是\(appName)。"
        case .chat: user += "遇到合得来的同伴，停下来闲聊。对方风格：\(other ?? "同类")。"
        case .scold: user += "被撞了，正追着对方骂。对方风格：\(other ?? "路人")。"
        case .reflect: user += "安静下来，回想一件亲历的事，说出此刻冒出的一个疑问。让思考符合你的成长阶段。"
        }
        return await ask(user)
    }

    private func ask(_ user: String) async -> String? {
        var req = URLRequest(url: URL(string: "http://127.0.0.1:11434/api/chat")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 12
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": Self.model,
            "stream": false,
            "think": false,
            "keep_alive": "5m",
            "messages": [
                [
                    "role": "system",
                    "content": "小四足机器人。只回一句中文口语，最多14字。不要解释，不要引号，不要写出编号或性格类型。",
                ],
                ["role": "user", "content": user],
            ],
            "options": [
                "num_ctx": 4096,
                "num_predict": 64,
                "temperature": 0.95,
                "top_p": 0.9,
            ],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        req.httpBody = data
        guard let (raw, _) = try? await URLSession.shared.data(for: req),
              let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any]
        else { return nil }
        let text = extract(obj)
        return clean(text)
    }

    private func extract(_ obj: [String: Any]) -> String {
        if let msg = obj["message"] as? [String: Any], let c = msg["content"] as? String { return c }
        if let c = obj["response"] as? String { return c }
        return ""
    }

    private func clean(_ raw: String) -> String? {
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
}

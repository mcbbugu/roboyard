import Combine
import Foundation

enum AppLang: String, CaseIterable {
    case zh
    case en

    static let defaultsKey = "critter.lang"

    var label: String {
        switch self {
        case .zh: "中文"
        case .en: "English"
        }
    }

    static var current: AppLang {
        if let raw = UserDefaults.standard.string(forKey: defaultsKey),
           let lang = AppLang(rawValue: raw) {
            return lang
        }
        let code = Locale.current.language.languageCode?.identifier ?? "zh"
        return code.hasPrefix("zh") ? .zh : .en
    }

    static func set(_ lang: AppLang) {
        UserDefaults.standard.set(lang.rawValue, forKey: defaultsKey)
    }
}

@MainActor
final class Voice: ObservableObject {
    static let shared = Voice()
    @Published private(set) var stamp = 0
    var lang: AppLang { .current }

    func set(_ lang: AppLang) {
        AppLang.set(lang)
        stamp += 1
    }
}

struct Copy {
    let lang: AppLang
    static var ui: Copy { Copy(lang: .current) }

    func t(_ zh: String, _ en: String) -> String { lang == .zh ? zh : en }

    func robot(_ id: Int) -> String {
        lang == .zh ? String(format: "%02d 号", id) : String(format: "No. %02d", id)
    }

    var appName: String { t("桌面机器人", "RoboYard") }
    var hidden: String { t("桌面机器人 · 已隐藏", "RoboYard · hidden") }
    var showRobots: String { t("显示机器人", "Show robots") }
    var warehouseMenu: String { t("仓库…", "Warehouse…") }
    var journalMenu: String { t("成长记录…", "Journal…") }
    var quit: String { t("退出", "Quit") }
    var language: String { t("语言", "Language") }
    func deskCap(_ n: Int) -> String { t("桌上最多：\(n) 只", "Desk cap: \(n)") }
    func countLabel(_ n: Int) -> String { t("\(n) 只", "\(n)") }
    var useOllama: String { t("使用本地 Ollama", "Use local Ollama") }
    var useDeepSeek: String { t("使用云端 DeepSeek", "Use cloud DeepSeek") }
    var editKey: String { t("填入 DeepSeek Key…", "DeepSeek key…") }
    var talkSource: String { t("对话来源", "Voice") }
    var talkInfo: String {
        t("本地走 Ollama。云端填 DeepSeek API Key 即可，默认 deepseek-chat。没连上就沉默。云端会把台词提示发到 DeepSeek。",
          "Ollama locally, or paste a DeepSeek API key (default deepseek-chat). No model means silence. Cloud sends the speech prompt to DeepSeek.")
    }
    var localOllama: String { t("本地 Ollama", "Local Ollama") }
    var cloudDeepSeek: String { t("云端 DeepSeek", "Cloud DeepSeek") }
    var ollamaAddr: String { t("Ollama 地址", "Ollama URL") }
    var ok: String { t("好", "OK") }
    var cancel: String { t("取消", "Cancel") }

    func ollamaStatus(_ reach: CritterTalk.Reachability, model: String) -> String {
        switch reach {
        case .unknown: return t("Ollama · 未检测", "Ollama · not checked")
        case .connected: return "Ollama · \(model)"
        case .unreachable: return t("Ollama · 未连接（沉默）", "Ollama · offline (silent)")
        }
    }

    func deepseekStatus(_ reach: CritterTalk.Reachability, model: String, hasKey: Bool) -> String {
        if !hasKey { return t("DeepSeek · 未填密钥", "DeepSeek · no API key") }
        switch reach {
        case .unknown: return t("DeepSeek · 未检测", "DeepSeek · not checked")
        case .connected: return "DeepSeek · \(model)"
        case .unreachable: return t("DeepSeek · 未连接（沉默）", "DeepSeek · offline (silent)")
        }
    }

    var journalTitle: String { t("机器人的成长记录", "How they grow") }
    var warehouseTitle: String { t("仓库", "Warehouse") }
    var journalLead: String { t("它们正在成为自己", "They are becoming themselves") }
    var journalBlurb: String { t("经历写成文字，文字成为身体。成长由累计文本量决定。", "Experience becomes text, text becomes body. Growth is cumulative words.") }
    var journalLadder: String { t("初生 → 2 千字·好奇 → 2 万字·沉思 → 10 万字·觉醒", "newborn → 2k curious → 20k thoughtful → 100k awakened") }
    func journalMeta(code: String, chars: String, events: String) -> String {
        t("\(code) · \(chars) 字 · \(events) 段经历", "\(code) · \(chars) chars · \(events) memories")
    }
    func chargeLine(_ percent: Int, post: String) -> String {
        t("电量 \(percent)% · \(post)", "\(percent)% · \(post)")
    }
    var powerSaver: String { t("省电模式（30fps）", "Power saver (30fps)") }
    var powerHint: String { t("降帧省电，静止时更少重绘", "Lower frame rate, fewer repaints when idle") }
    var shareAppName: String { t("台词带上应用名", "Include app names in prompts") }
    var shareAppHint: String { t("关掉后，对话提示不再包含窗口所属应用名", "Off: prompts never include window app names") }
    var cloudTitle: String { t("切换到云端对话？", "Switch to cloud dialogue?") }
    var cloudBody: String {
        t("云端会把台词提示（含记忆片段、应用名）发到 DeepSeek，会产生费用并离开本机。确定继续吗？",
          "Cloud sends speech prompts (memories, app names) to DeepSeek. It costs money and leaves this Mac. Continue?")
    }
    var continueCloud: String { t("继续用云端", "Use cloud") }
    var petClick: String { t("点按摸摸", "Click to pet") }
    var petHint: String { t("悄悄靠近再点，动作太快会吓跑它们", "Sneak up, then click — fast moves scare them off") }
    var feedDesk: String { t("给桌上加餐", "Feed the desk") }
    func feedWait(_ secs: Int) -> String { t("加餐冷却中（\(secs)s）", "Feeding cools down (\(secs)s)") }
    var renameTitle: String { t("给机器人取名", "Name this robot") }
    var renameBody: String { t("最多 12 字，清空恢复编号。", "Max 12 chars. Clear to restore its number.") }
    func petLine(_ id: Int) -> String {
        let zh = ["嘿嘿", "暖暖的", "再摸一下", "呼噜…"]
        let en = ["hehe", "warm", "again", "purr…"]
        let lines = lang == .zh ? zh : en
        return lines[abs(id) % lines.count]
    }
    func petted(_ name: String) -> String { t("被\(name)摸了摸", "petted by \(name)") }
    func fed(_ name: String) -> String { t("\(name)给桌上加了餐", "\(name) fed the desk") }
    func renamed(_ name: String) -> String { t("从此叫\(name)了", "now called \(name)") }
    var exportMemories: String { t("导出记忆", "Export memories") }
    var clearMemories: String { t("清空记忆…", "Erase memories…") }
    var clearTitle: String { t("清空所有记忆？", "Erase all memories?") }
    var clearBody: String { t("32 只机器人的经历、关系和字数都会清零，体型回到最小，不可撤销。", "All 32 robots lose experiences, relationships, and size. This cannot be undone.") }
    var clearConfirm: String { t("清空", "Erase") }
    func minutesLeft(_ mins: Int) -> String {
        t("还能在桌上约 \(mins) 分钟", "about \(mins) min left on desk")
    }
    var noMemories: String { t("还没有写下第一段经历。", "No memories yet.") }
    var journalFoot: String {
        t("减少显示数量不会抹掉记忆。原始经历保存在本机，模型每次只读取少量相关片段。",
          "Hiding robots does not erase them. Memories stay on this Mac; the model only sees a few.")
    }
    func readError(_ detail: String) -> String {
        t("已有记忆暂时无法读取，原文件已保留。\(detail)", "Couldn’t read memories; the original file is intact. \(detail)")
    }
    func saveError(_ detail: String) -> String {
        t("记忆尚未保存：\(detail)", "Memories not saved: \(detail)")
    }

    var warehouseLead: String { t("仓库", "Warehouse") }
    func warehouseBlurb(roster: Int, cap: Int) -> String {
        t("编制 \(roster) 只。桌上最多 \(cap) 只，剩下的在这儿充电。",
          "Roster of \(roster). At most \(cap) on the desk; the rest charge here.")
    }
    var deskCapPicker: String { t("桌上最多", "Desk cap") }
    var deskBay: String { t("桌上", "Desk") }
    var deskCaption: String { t("点卡片叫回来。它们会爬向菜单栏，进仓库后消失。", "Click a card to call them home. They climb to the menu bar and vanish.") }
    var deskEmpty: String { t("桌上现在没人。", "Nobody on the desk.") }
    var nestBay: String { t("仓库", "Warehouse") }
    var nestCaption: String { t("在里面充电。满了且桌上有空位，会自己爬出来。", "They charge here. Full, with a free desk slot, they crawl out.") }
    var nestEmpty: String { t("仓库空了。", "Warehouse is empty.") }
    func deskStat(on: Int, cap: Int) -> String { t("桌上 \(on)/\(cap)", "Desk \(on)/\(cap)") }
    func homingStat(_ n: Int) -> String { t("回家路上 \(n)", "Heading home \(n)") }
    func chargingStat(_ n: Int) -> String { t("仓库充电 \(n)", "Charging \(n)") }
    func nestStat(_ n: Int) -> String { t("仓库 \(n)", "Warehouse \(n)") }
    func summary(on: Int, cap: Int, nest: Int) -> String {
        t("桌上 \(on)/\(cap) · 仓库 \(nest)", "Desk \(on)/\(cap) · warehouse \(nest)")
    }

    func postTitle(_ post: ChargeLaw.Post) -> String {
        switch post {
        case .yard: t("在桌上", "on desk")
        case .homing: t("往回爬", "heading home")
        case .warehouse: t("仓库里", "in warehouse")
        case .emerging: t("爬出来", "coming out")
        }
    }

    func action(post: ChargeLaw.Post, refused: Bool, charged: Bool, worldVisible: Bool) -> String {
        if !worldVisible { return t("已隐藏", "Hidden") }
        if refused, post == .yard { return t("叫回来", "Call back") }
        switch post {
        case .warehouse: return charged ? t("派上桌", "Send out") : t("充电中", "Charging")
        case .yard: return t("叫回来", "Call back")
        case .homing: return t("正在回家", "Heading home")
        case .emerging: return t("正在出门", "Coming out")
        }
    }

    func hint(post: ChargeLaw.Post, canToggle: Bool, worldVisible: Bool) -> String {
        if !worldVisible { return t("先打开「显示机器人」。", "Turn on “Show robots” first.") }
        switch post {
        case .warehouse:
            return canToggle
                ? t("从仓库派到桌上。桌上满了会换走电最少的。", "Send onto the desk. A full desk swaps out the lowest battery.")
                : t("电还没够，充好会自己出来。", "Still charging. They come out when full.")
        case .yard:
            return t("叫回仓库充电。不是点桌面上的机器人。", "Call them back to charge. This isn’t clicking the desktop robot.")
        case .homing:
            return t("正往菜单栏走，到了就进仓库消失。", "Walking to the menu bar, then they vanish into the warehouse.")
        case .emerging:
            return t("刚从仓库爬出来。点一下叫回去。", "Just crawled out. Click to send them back.")
        }
    }

    func stageTitle(_ stage: GrowthStage) -> String {
        switch stage {
        case .newborn: t("初生", "newborn")
        case .curious: t("好奇", "curious")
        case .thoughtful: t("沉思", "thoughtful")
        case .awakened: t("觉醒", "awakened")
        }
    }

    func outlook(_ stage: GrowthStage) -> String {
        switch stage {
        case .newborn:
            t("刚认识这个世界，只关心眼前的鼠标、同伴和脚下。语气直白，不谈维度。",
              "New here. Cares about the pointer, friends, and the floor. Plain talk, no dimensions.")
        case .curious:
            t("开始把现在与过去比较，认得老朋友，对重复出现的事情感到好奇。还不理解维度。",
              "Compares now with then, knows old friends, curious about repeats. Still no sense of a third axis.")
        case .thoughtful:
            t("会从自己的经历寻找规律，开始疑惑为什么总会遇到边界。语气克制，不说自己全知。",
              "Looks for patterns in what happened. Wonders why the edge always stops them. No omniscience.")
        case .awakened:
            t("已经在这个平面生活很久。开始猜想除了左右和上下，是否还有另一个方向；想办法理解和离开二维世界。只是在思考和尝试，不声称已经离开。",
              "Lived on this plane a long time. Suspects another direction besides left-right and up-down. Trying, not claiming escape.")
        }
    }

    func vibe(_ mbti: MBTI) -> String {
        switch mbti {
        case .intj: t("冷、短、嫌麻烦", "cold, short, impatient")
        case .intp: t("走神、突然抬杠", "drifts, then argues")
        case .entj: t("下令、不耐烦", "gives orders, impatient")
        case .entp: t("贫嘴、开玩笑", "jokey, needling")
        case .infj: t("轻声、心软", "quiet, soft")
        case .infp: t("委屈、诗意一点点", "wounded, a little poetic")
        case .enfj: t("劝架、关心人", "peacemaker, cares")
        case .enfp: t("兴奋、大惊小怪", "excited, overreacts")
        case .istj: t("按规矩、纠正", "by the book, corrects")
        case .isfj: t("担心、叮嘱", "worries, reminds")
        case .estj: t("催、嫌慢", "hurries people")
        case .esfj: t("热络、拉家常", "chatty, neighborly")
        case .istp: t("懒得说、酷", "spare, cool")
        case .isfp: t("小声、害羞", "soft-spoken, shy")
        case .estp: t("冲、不怕事", "rushes in")
        case .esfp: t("嗨、起哄", "loud, cheers")
        }
    }

    func chatted(_ other: Int) -> String { t("又和\(other)号聊了一会儿", "chatted with No. \(other) again") }
    func bumped(_ other: Int) -> String { t("和\(other)号撞在了一起", "bumped into No. \(other)") }
    func edge(_ edge: Int) -> String {
        let side = ["下", "右", "上", "左"][edge]
        let en = ["bottom", "right", "top", "left"][edge]
        return t("走到世界的\(side)边，再往前就走不动了", "hit the \(en) edge of the world and couldn’t go on")
    }
    func linger(at app: String) -> String { t("陪着人待在\(app)旁边", "stayed by \(app) with someone") }
    var flee: String { t("鼠标靠得太近，我跑开了", "the pointer got too close, I ran") }
    var justArrived: String { t("刚刚来到桌面", "just arrived on the desk") }
    func familiar(_ id: Int, times: Int) -> String {
        t("最熟悉\(id)号，一起聊过\(times)次。", "closest with No. \(id), \(times) chats.")
    }
    func bondBadge(_ level: Int) -> String {
        switch level {
        case 3: return t("挚友", "best pals")
        case 2: return t("老友", "old pals")
        default: return t("熟人", "familiar")
        }
    }
    func chatOpenFor(other: String, meetings: Int, pal: Bool) -> String {
        if meetings >= 12 {
            return t("老熟人\(other)又来了，直接接上你们聊过的事开头。",
                     "Your best pal \(other) is back. Pick up where you left off.")
        }
        if meetings >= 3 {
            return t("你开口跟老朋友说话。对方风格：\(other)。聊点你们之前聊过的那种话题。",
                     "You greet an old friend. Their vibe: \(other). Talk like you have history.")
        }
        return chatOpen(other)
    }
    func withPal(_ id: String, times: Int) -> String {
        t("眼前是\(id)号，你们聊过\(times)次。", "No. \(id) is here; you’ve talked \(times) times.")
    }
    func walked(_ names: String) -> String {
        t("已经亲自走到过\(names)边。", "has walked to the \(names) edge.")
    }
    func edgeName(_ edge: Int) -> String {
        lang == .zh ? ["下", "右", "上", "左"][edge] : ["bottom", "right", "top", "left"][edge]
    }
    var edgeJoin: String { t("、", ", ") }
    func memoryPrompt(name: String, stage: String, outlook: String, extra: String, clips: String) -> String {
        t("你是\(name)，成长阶段：\(stage)。\(outlook)\(extra)记忆片段：\(clips)。台词要符合这些经历，不要编造未发生的往事。",
          "You are \(name), stage: \(stage). \(outlook)\(extra)Memories: \(clips). Stay true to these; don’t invent what didn’t happen.")
    }

    var systemPrompt: String {
        t("小四足机器人。只回一句中文口语，最多14字。不要解释，不要引号，不要写出编号或性格类型。",
          "Tiny four-legged robot. Reply with one casual English line, 12 words max. No explanation, no quotes, no ID or personality type.")
    }
    var speakStyle: String { t("说话风格", "Voice") }
    var oneLine: String { t("只说那一句台词。", "Say only that one line.") }
    var desktop: String { t("桌面", "the desktop") }
    var fleeCue: String { t("鼠标贴过来了，边跑边喊。", "The pointer is right on you. Yell while running.") }
    func lingerCue(_ app: String) -> String { t("人盯着\(app)很久了。", "Someone has been staring at \(app) for a while.") }
    func idleCue(_ app: String) -> String { t("停在原地歇着，眼前是\(app)。", "Resting in place. In front of you: \(app).") }
    func chatOpen(_ other: String) -> String {
        t("你开口跟眼前的同伴说话。对方风格：\(other)。抛一句对方接得上的话。",
          "You start talking to the robot in front of you. Their vibe: \(other). Toss a line they can answer.")
    }
    func scoldCue(_ other: String) -> String {
        t("被撞了，正追着对方骂。对方风格：\(other)。",
          "You got bumped. You’re scolding them. Their vibe: \(other).")
    }
    func scoldCueFor(other: String, collisions: Int) -> String {
        if collisions >= 6 {
            return t("又是\(other)！都撞第\(collisions)次了，新仇旧账一起算。",
                     "It’s \(other) AGAIN — collision number \(collisions). Settle it all now.")
        }
        return scoldCue(other)
    }
    var quietNights: String { t("夜间安静（23–7 点）", "Quiet nights (11pm–7am)") }
    var quietHint: String { t("半夜只跑不说话，锁屏时也一样", "They run silent at night and while locked") }
    var onboardTitle: String { t("欢迎来到 RoboYard", "Welcome to RoboYard") }
    var onboardBody: String {
        t("1）在桌面上点它们可以摸摸；2）菜单栏能加餐、开仓库；3）装个 Ollama 并 pull qwen3.5:2b，它们就会说话。半夜它们会自动安静。",
          "1) Click them to pet. 2) The menu bar feeds and opens the warehouse. 3) Install Ollama + pull qwen3.5:2b and they talk. They go quiet at night.")
    }
    var reflectCue: String {
        t("安静下来，回想一件亲历的事，说出此刻冒出的一个疑问。让思考符合你的成长阶段。",
          "Quiet down. Recall something you lived, then say the question that pops up. Match your growth stage.")
    }
    var reflectMilestone: String {
        t("你已经走遍世界的四边，每一边都撞过墙。把这件事说出来，再问一个关于世界之外的具体问题：除了左右上下，是否还有另一个方向？",
          "You have walked all four edges and hit every wall. Say so, then ask one concrete question about beyond: is there another direction besides left-right and up-down?")
    }
    var milestoneBadge: String { t("走遍四边", "edge-walker") }
    func chatFollow(_ line: String) -> String {
        t("你在和同伴对话。对方刚说：\(line)。必须接这一句，问答、顺着说或轻轻反驳都行，不要另起一个无关话题。",
          "You’re in a conversation. They just said: \(line). Answer that line — question, follow, or mild pushback. Don’t change the subject.")
    }
    var palFallback: String { t("同类", "another robot") }
    var strangerFallback: String { t("路人", "a stranger") }
    var maxLine: Int { lang == .zh ? 18 : 28 }
}

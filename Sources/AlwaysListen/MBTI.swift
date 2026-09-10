import Foundation

enum MBTI: Int, CaseIterable {
    case intj, intp, entj, entp, infj, infp, enfj, enfp
    case istj, isfj, estj, esfj, istp, isfp, estp, esfp

    var code: String {
        switch self {
        case .intj: "INTJ"
        case .intp: "INTP"
        case .entj: "ENTJ"
        case .entp: "ENTP"
        case .infj: "INFJ"
        case .infp: "INFP"
        case .enfj: "ENFJ"
        case .enfp: "ENFP"
        case .istj: "ISTJ"
        case .isfj: "ISFJ"
        case .estj: "ESTJ"
        case .esfj: "ESFJ"
        case .istp: "ISTP"
        case .isfp: "ISFP"
        case .estp: "ESTP"
        case .esfp: "ESFP"
        }
    }

    var group: String {
        switch self {
        case .intj, .intp, .entj, .entp: "NT"
        case .infj, .infp, .enfj, .enfp: "NF"
        case .istj, .isfj, .estj, .esfj: "SJ"
        case .istp, .isfp, .estp, .esfp: "SP"
        }
    }

    func fits(_ other: MBTI) -> Bool {
        if self == other { return true }
        if group == other.group { return true }
        let a = [code, other.code].sorted().joined(separator: "-")
        return Self.golden.contains(a)
    }

    private static let golden: Set<String> = [
        "ENFJ-INFP", "ENFP-INFJ", "ENFP-INTJ", "ENTJ-INTP",
        "ENTP-INTJ", "ESFJ-ISFP", "ESFP-ISTJ", "ESTP-ISFJ",
    ]

    var vibe: String {
        switch self {
        case .intj: "冷、短、嫌麻烦"
        case .intp: "走神、突然抬杠"
        case .entj: "下令、不耐烦"
        case .entp: "贫嘴、开玩笑"
        case .infj: "轻声、心软"
        case .infp: "委屈、诗意一点点"
        case .enfj: "劝架、关心人"
        case .enfp: "兴奋、大惊小怪"
        case .istj: "按规矩、纠正"
        case .isfj: "担心、叮嘱"
        case .estj: "催、嫌慢"
        case .esfj: "热络、拉家常"
        case .istp: "懒得说、酷"
        case .isfp: "小声、害羞"
        case .estp: "冲、不怕事"
        case .esfp: "嗨、起哄"
        }
    }

    func fallback(_ event: CritterTalk.Event) -> String {
        switch (self, event) {
        case (.intj, .flee): "离远点"
        case (.intj, .bump): "让开"
        case (.intp, .flee): "啊？跑？"
        case (.intp, .bump): "你是实体？"
        case (.entj, .flee): "立刻撤离"
        case (.entj, .bump): "排队"
        case (.entp, .flee): "鼠标来抢戏"
        case (.entp, .bump): "撞出火花了"
        case (.infj, .flee): "轻一点…"
        case (.infj, .bump): "没事吧"
        case (.infp, .flee): "好突然"
        case (.infp, .bump): "对不起啦"
        case (.enfj, .flee): "大家跟上"
        case (.enfj, .bump): "小心点呀"
        case (.enfp, .flee): "哇跑起来！"
        case (.enfp, .bump): "嘿你好啊"
        case (.istj, .flee): "按规定躲避"
        case (.istj, .bump): "看路"
        case (.isfj, .flee): "别被点到"
        case (.isfj, .bump): "撞疼没"
        case (.estj, .flee): "快散"
        case (.estj, .bump): "你挡道了"
        case (.esfj, .flee): "快来这边"
        case (.esfj, .bump): "哎呀对不住"
        case (.istp, .flee): "嗯走了"
        case (.istp, .bump): "哦"
        case (.isfp, .flee): "躲一下…"
        case (.isfp, .bump): "抱歉"
        case (.estp, .flee): "冲对面"
        case (.estp, .bump): "再来"
        case (.esfp, .flee): "散场啦"
        case (.esfp, .bump): "碰杯！"
        case (_, .linger): "还盯着啊"
        case (_, .idle): "晃着呢"
        case (_, .chat): "嘿"
        case (_, .scold): "站住"
        case (_, .reflect): "我好像记得这里"
        case (_, .flee): "跑"
        case (_, .bump): "借过"
        }
    }
}

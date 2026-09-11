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

}

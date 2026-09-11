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

    var vibe: String { Copy.ui.vibe(self) }

}

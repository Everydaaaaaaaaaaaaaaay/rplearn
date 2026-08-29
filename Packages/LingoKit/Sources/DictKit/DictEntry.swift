import Foundation

public struct DictSense: Sendable, Equatable, Identifiable {
    public let rank: Int
    public let partOfSpeech: String
    public let definition: String
    public let examples: [String]
    public let synonyms: [String]

    public var id: String { "\(partOfSpeech)-\(rank)-\(definition)" }

    public var partOfSpeechLabel: String {
        DictPartOfSpeechDisplay.label(for: partOfSpeech)
    }
}

enum DictPartOfSpeechDisplay {
    private static let abbreviationsByLabel: [String: String] = [
        "名词": "n.",
        "动词": "v.",
        "形容词": "adj.",
        "副词": "adv.",
        "介词": "prep.",
        "代词": "pron.",
        "连词": "conj.",
        "感叹词": "interj.",
        "助动词": "aux.",
        "数词": "num.",
        "冠词": "art.",
        "及物动词": "vt.",
        "不及物动词": "vi.",
        "现在分词": "v.",
        "过去式": "v.",
        "过去分词": "v.",
        "第三人称单数": "v.",
        "复数": "n.",
        "比较级": "adj.",
        "最高级": "adj.",
    ]

    static let prefixedLabels: [(prefix: String, label: String)] = [
        ("prep.", "介词"),
        ("pron.", "代词"),
        ("conj.", "连词"),
        ("interj.", "感叹词"),
        ("aux.", "助动词"),
        ("adv.", "副词"),
        ("adj.", "形容词"),
        ("num.", "数词"),
        ("art.", "冠词"),
        ("vt.", "及物动词"),
        ("vi.", "不及物动词"),
        ("a.", "形容词"),
        ("ad.", "副词"),
        ("n.", "名词"),
        ("v.", "动词"),
    ]

    static func label(for code: String) -> String {
        switch code.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
        case "n", "n.": "名词"
        case "v", "v.": "动词"
        case "a", "a.", "s", "adj.": "形容词"
        case "r", "ad.", "adv.": "副词"
        case "prep.": "介词"
        case "pron.": "代词"
        case "conj.": "连词"
        case "interj.": "感叹词"
        case "aux.": "助动词"
        case "num.": "数词"
        case "art.": "冠词"
        case "vt.": "及物动词"
        case "vi.": "不及物动词"
        default: code
        }
    }

    static func abbreviation(forCode code: String) -> String? {
        abbreviation(forLabel: label(for: code))
    }

    static func abbreviation(forLabel label: String) -> String? {
        abbreviationsByLabel[label]
    }

    /// WordNet 只区分一般动词，而 ECDICT 还会细分及物/不及物动词。
    /// 展示例句释义时允许同一词性族互相匹配，但绝不跨词性回退。
    static func labelsAreCompatible(_ lhs: String, _ rhs: String) -> Bool {
        lexicalFamily(for: lhs) == lexicalFamily(for: rhs)
    }

    private static func lexicalFamily(for labelOrCode: String) -> String {
        switch label(for: labelOrCode) {
        case "及物动词", "不及物动词": "动词"
        default: label(for: labelOrCode)
        }
    }

    static func explicitLabel(forBracketLabel label: String) -> String? {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if abbreviationsByLabel[trimmed] != nil {
            return trimmed
        }
        let normalized = trimmed.lowercased()
        if let match = prefixedLabels.first(where: {
            normalized == $0.prefix.trimmingCharacters(in: CharacterSet(charactersIn: "."))
                || normalized == $0.prefix
        }) {
            return match.label
        }
        return ["pl", "pl."].contains(normalized) ? "名词" : nil
    }

    static func expandedDomainLabel(_ label: String) -> String {
        switch label.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "化": "化学"
        case "医": "医学"
        case "计": "计算机"
        case "经": "经济"
        case "法": "法律"
        default: label
        }
    }

    static func splitPrefixedDefinition(
        _ line: String
    ) -> (label: String, definition: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        for item in prefixedLabels where lowered.hasPrefix(item.prefix) {
            let definition = trimmed.dropFirst(item.prefix.count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (item.label, definition)
        }
        return nil
    }
}

public struct DictMeaningGroup: Sendable, Equatable, Identifiable {
    public let partOfSpeech: String?
    public let meaning: String

    public var id: String { "\(partOfSpeech ?? "其它")-\(meaning)" }

    /// 中文词性对应的常用英文缩写；未知或缺失词性不臆测。
    public var partOfSpeechAbbreviation: String? {
        guard let partOfSpeech else { return nil }
        return DictPartOfSpeechDisplay.abbreviation(forLabel: partOfSpeech)
    }
}

public struct DictWordForm: Sendable, Equatable, Identifiable {
    public let label: String
    public let word: String

    public var id: String { "\(label)-\(word)" }
}

/// 本地学习词典的一条词目：ECDICT 提供英汉信息，WordNet 提供结构化英文义项与例句。
public struct DictEntry: Sendable, Equatable {
    /// 原始拼写（保留大小写，如 "OK"）。
    public var word: String
    public var phonetic: String?
    /// ECDICT 的平铺英文释义；已有 WordNet 结构化义项时不重复存储。
    public var definition: String?
    /// 中文释义，行间以字面量 "\n" 分隔。
    public var translation: String?
    public var pos: String?
    public var collins: Int
    public var oxford: Bool
    /// 考试标签，空格分隔（zk/gk/cet4/cet6/ky/toefl/ielts/gre）。
    public var tag: String?
    public var bnc: Int
    public var frq: Int
    public var exchange: String?
    public var senses: [DictSense]

    public init(
        word: String,
        phonetic: String? = nil,
        definition: String? = nil,
        translation: String? = nil,
        pos: String? = nil,
        collins: Int = 0,
        oxford: Bool = false,
        tag: String? = nil,
        bnc: Int = 0,
        frq: Int = 0,
        exchange: String? = nil,
        senses: [DictSense] = []
    ) {
        self.word = word
        self.phonetic = phonetic
        self.definition = definition
        self.translation = translation
        self.pos = pos
        self.collins = collins
        self.oxford = oxford
        self.tag = tag
        self.bnc = bnc
        self.frq = frq
        self.exchange = exchange
        self.senses = senses
    }

    /// 释义按行拆开（数据里换行是字面量 "\n" 两个字符）。
    public var translationLines: [String] {
        guard let translation else { return [] }
        return translation
            .replacingOccurrences(of: "\\n", with: "\n")
            .split(separator: "\n")
            .map(String.init)
    }

    public var meaningGroups: [DictMeaningGroup] {
        let fallbackPartOfSpeech = inferredMeaningPartOfSpeechLabel
        return translationLines.map { line in
            let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
            for (prefix, label) in DictPartOfSpeechDisplay.prefixedLabels {
                guard value.lowercased().hasPrefix(prefix) else { continue }
                let meaning = value.dropFirst(prefix.count)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !meaning.isEmpty {
                    return DictMeaningGroup(partOfSpeech: label, meaning: meaning)
                }
            }
            if value.hasPrefix("["), let end = value.firstIndex(of: "]") {
                let sourceLabel = String(value[value.index(after: value.startIndex)..<end])
                let meaning = value[value.index(after: end)...]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !meaning.isEmpty {
                    if let label = DictPartOfSpeechDisplay.explicitLabel(
                        forBracketLabel: sourceLabel
                    ) {
                        return DictMeaningGroup(partOfSpeech: label, meaning: meaning)
                    }
                    let domain = DictPartOfSpeechDisplay.expandedDomainLabel(sourceLabel)
                    return DictMeaningGroup(
                        partOfSpeech: fallbackPartOfSpeech,
                        meaning: "【\(domain)】\(meaning)"
                    )
                }
            }
            return DictMeaningGroup(partOfSpeech: nil, meaning: value)
        }
        .filter { !$0.meaning.isEmpty }
    }

    private var inferredMeaningPartOfSpeechLabel: String {
        if wordForms.contains(where: {
            $0.label == "原形" && $0.word.caseInsensitiveCompare(word) != .orderedSame
        }), let form = wordForms.first(where: {
            $0.label != "原形" && $0.word.caseInsensitiveCompare(word) == .orderedSame
        }) {
            return form.label
        }

        let senseLabels = Set(senses.map(\.partOfSpeechLabel))
        if senseLabels.count == 1, let label = senseLabels.first {
            return label
        }
        return "释义"
    }

    public var fallbackEnglishDefinitions: [String] {
        guard senses.isEmpty, let definition else { return [] }
        return definition
            .replacingOccurrences(of: "\\n", with: "\n")
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    public var wordForms: [DictWordForm] {
        guard let exchange else { return [] }
        var seen = Set<String>()
        return exchange.split(separator: "/").compactMap { item in
            let pair = item.split(separator: ":", maxSplits: 1).map(String.init)
            guard pair.count == 2,
                  let label = Self.wordFormLabels[pair[0]],
                  !pair[1].isEmpty
            else { return nil }
            let identity = "\(label)-\(pair[1])"
            guard seen.insert(identity).inserted else { return nil }
            return DictWordForm(label: label, word: pair[1])
        }
    }

    public var tags: [String] {
        tag?.split(separator: " ").map(String.init) ?? []
    }

    private static let wordFormLabels: [String: String] = [
        "0": "原形",
        "p": "过去式",
        "d": "过去分词",
        "i": "现在分词",
        "3": "第三人称单数",
        "s": "复数",
        "r": "比较级",
        "t": "最高级",
    ]
}

import CoreKit
import DesignSystem
import SwiftUI

/// 词典卡内容目标：单词或语法点，卡内栈式跳转（原信息替换显示）。
public enum DictTarget: Hashable, Sendable {
    case word(String)
    case grammarPoint(String)
    case grammarTerm(String)
}

/// 词典卡与收藏仓库之间的轻量接口，避免 DictKit 直接依赖具体持久化实现。
public struct WordFavoriteActions: Sendable {
    private let containsAction: @Sendable (String) async -> Bool
    private let toggleAction: @Sendable (String, String?) async -> Bool

    public init(
        contains: @escaping @Sendable (String) async -> Bool,
        toggle: @escaping @Sendable (String, String?) async -> Bool
    ) {
        self.containsAction = contains
        self.toggleAction = toggle
    }

    func contains(_ word: String) async -> Bool {
        await containsAction(word)
    }

    func toggle(_ word: String, translationZh: String?) async -> Bool {
        await toggleAction(word, translationZh)
    }
}

/// 一条例句的翻译请求。
///
/// 请求携带完整的语境与词典身份，避免同一句在不同词义下错误复用缓存。
public struct DictExampleTranslationRequest: Sendable, Hashable {
    public let sentence: String
    public let lemma: String
    public let partOfSpeech: String
    public let definitionEn: String?
    public let candidateMeaningsZhHans: [String]
    public let stableSenseId: String?
    public let dictionarySource: String
    public let dictionaryVersion: String

    public init(
        sentence: String,
        lemma: String = "",
        partOfSpeech: String = "",
        definitionEn: String? = nil,
        candidateMeaningsZhHans: [String] = [],
        stableSenseId: String? = nil,
        dictionarySource: String = "ecdict-wordnet",
        dictionaryVersion: String = "v1"
    ) {
        self.sentence = sentence
        self.lemma = lemma
        self.partOfSpeech = partOfSpeech
        self.definitionEn = definitionEn
        self.candidateMeaningsZhHans = candidateMeaningsZhHans
        self.stableSenseId = stableSenseId
        self.dictionarySource = dictionarySource
        self.dictionaryVersion = dictionaryVersion
    }

    fileprivate var normalized: Self {
        Self(
            sentence: DictDisplayText.normalizedWhitespace(sentence),
            lemma: lemma.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            partOfSpeech: partOfSpeech.trimmingCharacters(in: .whitespacesAndNewlines),
            definitionEn: definitionEn.map(DictDisplayText.normalizedWhitespace),
            candidateMeaningsZhHans: candidateMeaningsZhHans
                .map(DictDisplayText.normalizedWhitespace)
                .filter { !$0.isEmpty },
            stableSenseId: stableSenseId?.trimmingCharacters(in: .whitespacesAndNewlines),
            dictionarySource: dictionarySource.trimmingCharacters(in: .whitespacesAndNewlines),
            dictionaryVersion: dictionaryVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

/// 例句翻译以及目标词在该句中的最小必要语境义项。
public struct DictExampleTranslation: Sendable, Equatable {
    public let sentenceZhHans: String
    public let contextualMeaningZhHans: String?

    /// 暂时兼容尚未迁移的组合根调用方。
    public var sentenceZh: String { sentenceZhHans }
    public var meaningZh: String? { contextualMeaningZhHans }

    public init(sentenceZh: String) {
        self.sentenceZhHans = sentenceZh
        self.contextualMeaningZhHans = nil
    }

    public init(sentenceZhHans: String, contextualMeaningZhHans: String? = nil) {
        self.sentenceZhHans = sentenceZhHans
        self.contextualMeaningZhHans = contextualMeaningZhHans
    }
}

/// 词典例句翻译能力由组合根注入，DictKit 不直接依赖具体 LLM 服务。
public struct DictExampleTranslationActions: Sendable {
    private let translateAction: @Sendable (
        DictExampleTranslationRequest
    ) async -> DictExampleTranslation?

    public init(
        translate: @escaping @Sendable (
            DictExampleTranslationRequest
        ) async -> DictExampleTranslation?
    ) {
        self.translateAction = translate
    }

    func translate(_ request: DictExampleTranslationRequest) async -> DictExampleTranslation? {
        let request = request.normalized
        guard !request.sentence.isEmpty,
              let translated = await translateAction(request)
        else { return nil }

        let sentenceZh = DictDisplayText.normalizedWhitespace(translated.sentenceZhHans)
        guard !sentenceZh.isEmpty else { return nil }
        let meaningZh = translated.contextualMeaningZhHans
            .map(DictDisplayText.normalizedWhitespace)
            .flatMap { value in
                // Never let a malformed/model-generated list reintroduce the
                // original “all meanings” annotation bug.
                DictDisplayText.splitTopLevelMeanings(value).count == 1 ? value : nil
            }
        return DictExampleTranslation(
            sentenceZhHans: sentenceZh,
            contextualMeaningZhHans: meaningZh?.isEmpty == false ? meaningZh : nil
        )
    }

    /// Keeps the server's contextual meaning when available and uses the system
    /// translator only to fill the whole-sentence translation after a failure.
    public func fallingBackToSentenceTranslation(
        _ fallback: @escaping @Sendable (String) async -> String?
    ) -> Self {
        let primary = self
        return Self { request in
            if let translated = await primary.translate(request) {
                return translated
            }
            guard let sentenceZhHans = await fallback(request.sentence) else {
                return nil
            }
            return DictExampleTranslation(sentenceZhHans: sentenceZhHans)
        }
    }
}

actor DictExampleTranslationCache {
    static let shared = DictExampleTranslationCache()

    private var translations: [DictExampleTranslationRequest: DictExampleTranslation] = [:]
    private var inFlight: [
        DictExampleTranslationRequest: Task<DictExampleTranslation?, Never>
    ] = [:]

    func translation(
        for request: DictExampleTranslationRequest,
        using actions: DictExampleTranslationActions
    ) async -> DictExampleTranslation? {
        let key = request.normalized
        guard !key.sentence.isEmpty else { return nil }
        if let cached = translations[key] {
            return cached
        }
        if let pending = inFlight[key] {
            return await pending.value
        }

        let task = Task { await actions.translate(key) }
        inFlight[key] = task
        let translated = await task.value
        inFlight[key] = nil
        if let translated {
            translations[key] = translated
        }
        return translated
    }
}

enum DictCardLayout {
    static let width: CGFloat = 320
    static let maximumHeight: CGFloat = 340
    static let contentPadding: CGFloat = 10
    static let contentSpacing: CGFloat = 8
    static let partOfSpeechColumnWidth: CGFloat = 66
    static let definitionColumnSpacing: CGFloat = 6
    static var definitionColumnLeading: CGFloat {
        partOfSpeechColumnWidth + definitionColumnSpacing
    }
}

struct DictSenseDisplayGroup: Identifiable, Equatable {
    let partOfSpeech: String
    let senses: [DictSense]

    var id: String { partOfSpeech }
    var partOfSpeechLabel: String { senses.first?.partOfSpeechLabel ?? partOfSpeech }
    var definitionLines: [String] {
        senses.map { DictDisplayText.normalizedWhitespace($0.definition) }
    }
    var definitionText: String {
        definitionLines.joined(separator: ";\n")
    }
    var synonymText: String? {
        var seen = Set<String>()
        let synonyms = senses
            .flatMap(\.synonyms)
            .filter { seen.insert($0.lowercased()).inserted }
            .prefix(6)
        return synonyms.isEmpty
            ? nil
            : "≈ \(synonyms.joined(separator: " · "))"
    }
}

struct DictFallbackDefinitionDisplayGroup: Identifiable, Equatable {
    let partOfSpeechLabel: String
    let definitions: [String]

    var id: String { "\(partOfSpeechLabel)-\(definitions.joined())" }
    var definitionLines: [String] {
        definitions.map(DictDisplayText.normalizedWhitespace)
    }
    var definitionText: String {
        definitionLines.joined(separator: ";\n")
    }
}

struct DictUsageExample: Identifiable, Equatable {
    let senseID: String?
    let lemma: String
    let partOfSpeech: String
    let partOfSpeechLabel: String
    let partOfSpeechAbbreviation: String
    let definitionEn: String?
    let candidateMeaningsZhHans: [String]
    let meaningZh: String?
    let text: String

    init(
        senseID: String? = nil,
        lemma: String = "",
        partOfSpeech: String = "",
        partOfSpeechLabel: String,
        partOfSpeechAbbreviation: String,
        definitionEn: String? = nil,
        candidateMeaningsZhHans: [String] = [],
        meaningZh: String? = nil,
        text: String
    ) {
        self.senseID = senseID
        self.lemma = lemma
        self.partOfSpeech = partOfSpeech
        self.partOfSpeechLabel = partOfSpeechLabel
        self.partOfSpeechAbbreviation = partOfSpeechAbbreviation
        self.definitionEn = definitionEn
        self.candidateMeaningsZhHans = candidateMeaningsZhHans
        self.meaningZh = meaningZh
        self.text = text
    }

    var id: String { "\(senseID ?? partOfSpeechAbbreviation)-\(text)" }
    var annotation: String { annotation(meaningZh: nil) }

    func annotation(meaningZh contextualMeaning: String?) -> String {
        let displayMeaning = contextualMeaning ?? self.meaningZh
        guard let displayMeaning, !displayMeaning.isEmpty else {
            return "（\(partOfSpeechAbbreviation)）"
        }
        return "（\(partOfSpeechAbbreviation) \(displayMeaning)）"
    }

    var translationRequest: DictExampleTranslationRequest {
        DictExampleTranslationRequest(
            sentence: text,
            lemma: lemma,
            partOfSpeech: partOfSpeech,
            definitionEn: definitionEn,
            candidateMeaningsZhHans: candidateMeaningsZhHans,
            stableSenseId: senseID
        )
    }
}

struct DictUsageExampleGroup: Identifiable, Equatable {
    let partOfSpeechLabel: String
    let partOfSpeechAbbreviation: String
    let examples: [DictUsageExample]

    var id: String { partOfSpeechAbbreviation }
}

enum DictDisplayText {
    static func normalizedWhitespace(_ text: String) -> String {
        text
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 拆分 ECDICT 中文释义中的顶层义项；括号/方括号/书名号内的逗号和分号不拆分。
    static func splitTopLevelMeanings(_ text: String) -> [String] {
        let opening: Set<Character> = ["(", "（", "[", "［", "{", "｛", "【", "『", "〈", "《"]
        let closing: Set<Character> = [")", "）", "]", "］", "}", "｝", "】", "』", "〉", "》"]
        let separators: Set<Character> = [",", "，", ";", "；"]
        var depth = 0
        var current = ""
        var results: [String] = []

        func flush() {
            let value = normalizedWhitespace(current)
            if !value.isEmpty { results.append(value) }
            current = ""
        }

        for character in text {
            if opening.contains(character) {
                depth += 1
            } else if closing.contains(character) {
                depth = max(0, depth - 1)
            }
            if separators.contains(character), depth == 0 {
                flush()
            } else {
                current.append(character)
            }
        }
        flush()
        return results
    }

}

enum DictSenseDisplayPolicy {
    static func groups(for senses: [DictSense]) -> [DictSenseDisplayGroup] {
        var orderedPartsOfSpeech: [String] = []
        var sensesByPartOfSpeech: [String: [DictSense]] = [:]

        for sense in senses {
            if sensesByPartOfSpeech[sense.partOfSpeech] == nil {
                orderedPartsOfSpeech.append(sense.partOfSpeech)
            }
            sensesByPartOfSpeech[sense.partOfSpeech, default: []].append(sense)
        }

        return orderedPartsOfSpeech.map { partOfSpeech in
            DictSenseDisplayGroup(
                partOfSpeech: partOfSpeech,
                senses: sensesByPartOfSpeech[partOfSpeech] ?? []
            )
        }
    }

    /// ECDICT 的英文释义会把一个义项折成多条缩进续行；这里先恢复完整句子，
    /// 再按中文词性分组，避免把 pron./conj. 和换行符暴露给用户。
    static func fallbackGroups(
        for definitions: [String]
    ) -> [DictFallbackDefinitionDisplayGroup] {
        var results: [DictFallbackDefinitionDisplayGroup] = []
        var currentLabel = "释义"
        var currentDefinitions: [String] = []

        func flush() {
            guard !currentDefinitions.isEmpty else { return }
            results.append(
                DictFallbackDefinitionDisplayGroup(
                    partOfSpeechLabel: currentLabel,
                    definitions: currentDefinitions
                )
            )
            currentDefinitions = []
        }

        for rawLine in definitions {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if let prefixed = DictPartOfSpeechDisplay.splitPrefixedDefinition(trimmed) {
                flush()
                currentLabel = prefixed.label
                if !prefixed.definition.isEmpty {
                    currentDefinitions = [prefixed.definition]
                }
                continue
            }

            let isContinuation = rawLine.first?.isWhitespace == true
            if isContinuation, let lastIndex = currentDefinitions.indices.last {
                currentDefinitions[lastIndex] += " \(trimmed)"
            } else {
                currentDefinitions.append(trimmed)
            }
        }
        flush()
        return results
    }
}

enum DictUsageExamplePolicy {
    private struct PartOfSpeechDescriptor {
        let id: String
        let partOfSpeech: String
        let label: String
        let abbreviation: String
        let meaningZh: String?
        let candidateMeaningsZhHans: [String]
        let senseID: String?
        let definitionEn: String?
    }

    static func groups(
        for entry: DictEntry,
        limit: Int = 4,
        perPartOfSpeechLimit: Int = 2
    ) -> [DictUsageExampleGroup] {
        guard limit > 0, perPartOfSpeechLimit > 0 else { return [] }
        var results: [DictUsageExample] = []
        var seen = Set<String>()
        var countsByPartOfSpeech: [String: Int] = [:]

        func append(_ text: String, descriptor: PartOfSpeechDescriptor) {
            guard results.count < limit,
                  countsByPartOfSpeech[descriptor.id, default: 0] < perPartOfSpeechLimit
            else { return }
            let normalized = DictDisplayText.normalizedWhitespace(text)
            guard !normalized.isEmpty,
                  seen.insert(normalized.lowercased()).inserted
            else { return }
            results.append(
                DictUsageExample(
                    senseID: descriptor.senseID,
                    lemma: entry.word,
                    partOfSpeech: descriptor.partOfSpeech,
                    partOfSpeechLabel: descriptor.label,
                    partOfSpeechAbbreviation: descriptor.abbreviation,
                    definitionEn: descriptor.definitionEn,
                    candidateMeaningsZhHans: descriptor.candidateMeaningsZhHans,
                    meaningZh: descriptor.meaningZh,
                    text: normalized
                )
            )
            countsByPartOfSpeech[descriptor.id, default: 0] += 1
        }

        let senseGroups = DictSenseDisplayPolicy.groups(for: entry.senses)
        let descriptors = senseGroups.map { descriptor(for: $0, entry: entry) }
        // 先让尚未出现的词性各获得一句，再为每个词性补到最多两句。
        for (group, baseDescriptor) in zip(senseGroups, descriptors)
        where countsByPartOfSpeech[baseDescriptor.id, default: 0] == 0 {
            if let sense = group.senses.first(where: { !$0.examples.isEmpty }),
               let example = sense.examples.first {
                append(
                    example,
                    descriptor: descriptor(for: sense, in: group, fallback: baseDescriptor)
                )
            }
        }
        for (group, baseDescriptor) in zip(senseGroups, descriptors) {
            for sense in group.senses {
                let exampleDescriptor = descriptor(
                    for: sense,
                    in: group,
                    fallback: baseDescriptor
                )
                for example in sense.examples {
                    append(example, descriptor: exampleDescriptor)
                }
            }
        }

        var orderedIDs: [String] = []
        var examplesByID: [String: [DictUsageExample]] = [:]
        for example in results {
            let id = example.partOfSpeechAbbreviation
            if examplesByID[id] == nil {
                orderedIDs.append(id)
            }
            examplesByID[id, default: []].append(example)
        }
        return orderedIDs.compactMap { id in
            guard let examples = examplesByID[id], let first = examples.first else { return nil }
            return DictUsageExampleGroup(
                partOfSpeechLabel: first.partOfSpeechLabel,
                partOfSpeechAbbreviation: first.partOfSpeechAbbreviation,
                examples: examples
            )
        }
    }

    private static func descriptor(
        for group: DictSenseDisplayGroup,
        entry: DictEntry
    ) -> PartOfSpeechDescriptor {
        let label = group.partOfSpeechLabel
        let abbreviation = DictPartOfSpeechDisplay.abbreviation(forCode: group.partOfSpeech)
            ?? DictPartOfSpeechDisplay.abbreviation(forLabel: label)
            ?? group.partOfSpeech
        let matchingMeanings = entry.meaningGroups
            .filter { meaningGroup in
                guard let meaningLabel = meaningGroup.partOfSpeech else { return false }
                return meaningLabel == label
                    || DictPartOfSpeechDisplay.labelsAreCompatible(label, meaningLabel)
            }
            .flatMap { DictDisplayText.splitTopLevelMeanings($0.meaning) }
        let fallbackMeaning = matchingMeanings.count == 1 ? matchingMeanings.first : nil
        return PartOfSpeechDescriptor(
            id: abbreviation,
            partOfSpeech: group.partOfSpeech,
            label: label,
            abbreviation: abbreviation,
            meaningZh: fallbackMeaning,
            candidateMeaningsZhHans: matchingMeanings,
            senseID: nil,
            definitionEn: nil
        )
    }

    private static func descriptor(
        for sense: DictSense,
        in group: DictSenseDisplayGroup,
        fallback: PartOfSpeechDescriptor
    ) -> PartOfSpeechDescriptor {
        return PartOfSpeechDescriptor(
            id: fallback.id,
            partOfSpeech: sense.partOfSpeech,
            label: fallback.label,
            abbreviation: fallback.abbreviation,
            meaningZh: fallback.meaningZh,
            candidateMeaningsZhHans: fallback.candidateMeaningsZhHans,
            senseID: sense.id,
            definitionEn: DictDisplayText.normalizedWhitespace(sense.definition)
        )
    }

}

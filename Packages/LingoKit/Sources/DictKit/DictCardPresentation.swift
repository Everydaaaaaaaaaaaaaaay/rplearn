import CoreKit
import DesignSystem
import NaturalLanguage
import SwiftUI

/// 词典卡内容目标：单词或语法点，卡内栈式跳转（原信息替换显示）。
public enum DictTarget: Hashable, Sendable {
    case word(String)
    case grammarPoint(String)
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

/// 一条例句的翻译请求。模型只负责翻译整句，目标词词义始终取自本地中文词典。
public struct DictExampleTranslationRequest: Sendable, Hashable {
    public let sentence: String

    public init(sentence: String) {
        self.sentence = sentence
    }

    fileprivate var normalized: Self {
        Self(sentence: DictDisplayText.normalizedWhitespace(sentence))
    }
}

/// 例句的自然中文翻译。
public struct DictExampleTranslation: Sendable, Equatable {
    public let sentenceZh: String

    public init(sentenceZh: String) {
        self.sentenceZh = sentenceZh
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

        let sentenceZh = DictDisplayText.normalizedWhitespace(translated.sentenceZh)
        guard !sentenceZh.isEmpty else { return nil }
        return DictExampleTranslation(sentenceZh: sentenceZh)
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
    let partOfSpeechLabel: String
    let partOfSpeechAbbreviation: String
    let meaningZh: String?
    let text: String

    var id: String { "\(partOfSpeechAbbreviation)-\(text)" }
    var annotation: String {
        guard let meaningZh, !meaningZh.isEmpty else {
            return "（\(partOfSpeechAbbreviation)）"
        }
        return "（\(partOfSpeechAbbreviation) \(meaningZh)）"
    }

    var translationRequest: DictExampleTranslationRequest {
        DictExampleTranslationRequest(sentence: text)
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
        let label: String
        let abbreviation: String
        let meaningZh: String?
    }

    static func groups(
        for entry: DictEntry,
        requestedWord: String,
        contextText: String?,
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
                    partOfSpeechLabel: descriptor.label,
                    partOfSpeechAbbreviation: descriptor.abbreviation,
                    meaningZh: descriptor.meaningZh,
                    text: normalized
                )
            )
            countsByPartOfSpeech[descriptor.id, default: 0] += 1
        }

        let senseGroups = DictSenseDisplayPolicy.groups(for: entry.senses)
        let descriptors = senseGroups.map { descriptor(for: $0, entry: entry) }
        let matchingWords = [requestedWord, entry.word]
        if let contextual = contextualSentence(
            in: contextText,
            matching: matchingWords
        ) {
            var contextualDescriptor: PartOfSpeechDescriptor?
            if let inferredLabel = contextualPartOfSpeechLabel(
                in: contextual,
                matching: matchingWords
            ) {
                if let index = descriptors.firstIndex(where: { $0.label == inferredLabel }) {
                    contextualDescriptor = descriptorForContext(
                        descriptors[index],
                        senseGroup: senseGroups[index]
                    )
                } else {
                    contextualDescriptor = descriptor(
                        for: entry.meaningGroups.first { $0.partOfSpeech == inferredLabel }
                    )
                }
            } else if descriptors.count == 1 {
                contextualDescriptor = descriptorForContext(
                    descriptors[0],
                    senseGroup: senseGroups[0]
                )
            } else if entry.meaningGroups.count == 1 {
                contextualDescriptor = descriptor(for: entry.meaningGroups.first)
            }
            if let contextualDescriptor {
                append(contextual, descriptor: contextualDescriptor)
            }
        }

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
        let matchingMeaning = entry.meaningGroups.first { $0.partOfSpeech == label }
            ?? entry.meaningGroups.first { meaningGroup in
                guard let meaningLabel = meaningGroup.partOfSpeech else { return false }
                return DictPartOfSpeechDisplay.labelsAreCompatible(label, meaningLabel)
            }
        return PartOfSpeechDescriptor(
            id: abbreviation,
            label: label,
            abbreviation: abbreviation,
            meaningZh: matchingMeaning.map {
                DictDisplayText.normalizedWhitespace($0.meaning)
            }
        )
    }

    private static func descriptor(
        for meaningGroup: DictMeaningGroup?
    ) -> PartOfSpeechDescriptor? {
        guard let meaningGroup,
              let label = meaningGroup.partOfSpeech,
              let abbreviation = meaningGroup.partOfSpeechAbbreviation
        else { return nil }
        return PartOfSpeechDescriptor(
            id: abbreviation,
            label: label,
            abbreviation: abbreviation,
            meaningZh: DictDisplayText.normalizedWhitespace(meaningGroup.meaning)
        )
    }

    private static func descriptor(
        for sense: DictSense,
        in group: DictSenseDisplayGroup,
        fallback: PartOfSpeechDescriptor
    ) -> PartOfSpeechDescriptor {
        guard group.senses.count > 1 else { return fallback }
        return PartOfSpeechDescriptor(
            id: fallback.id,
            label: fallback.label,
            abbreviation: fallback.abbreviation,
            meaningZh: fallback.meaningZh
        )
    }

    private static func descriptorForContext(
        _ descriptor: PartOfSpeechDescriptor,
        senseGroup: DictSenseDisplayGroup
    ) -> PartOfSpeechDescriptor {
        guard senseGroup.senses.count > 1 else { return descriptor }
        return PartOfSpeechDescriptor(
            id: descriptor.id,
            label: descriptor.label,
            abbreviation: descriptor.abbreviation,
            meaningZh: descriptor.meaningZh
        )
    }

    private static func contextualPartOfSpeechLabel(
        in sentence: String,
        matching words: [String]
    ) -> String? {
        let candidates = Set(
            words
                .map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        guard !candidates.isEmpty else { return nil }

        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = sentence
        var inferredLabel: String?
        tagger.enumerateTags(
            in: sentence.startIndex..<sentence.endIndex,
            unit: .word,
            scheme: .lexicalClass,
            options: [.omitWhitespace, .omitPunctuation, .joinNames]
        ) { tag, tokenRange in
            let token = sentence[tokenRange].lowercased()
            guard candidates.contains(token) else { return true }
            switch tag {
            case .noun: inferredLabel = "名词"
            case .verb: inferredLabel = "动词"
            case .adjective: inferredLabel = "形容词"
            case .adverb: inferredLabel = "副词"
            case .pronoun: inferredLabel = "代词"
            case .conjunction: inferredLabel = "连词"
            case .preposition: inferredLabel = "介词"
            case .interjection: inferredLabel = "感叹词"
            default: break
            }
            return false
        }
        return inferredLabel
    }

    private static func contextualSentence(
        in contextText: String?,
        matching words: [String]
    ) -> String? {
        guard let contextText else { return nil }
        let candidates = words
            .map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !candidates.isEmpty else { return nil }

        var sentences: [String] = []
        contextText.enumerateSubstrings(
            in: contextText.startIndex..<contextText.endIndex,
            options: .bySentences
        ) { substring, _, _, _ in
            if let substring {
                sentences.append(substring.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        if sentences.isEmpty {
            sentences = [contextText.trimmingCharacters(in: .whitespacesAndNewlines)]
        }

        return sentences.first { sentence in
            let sentenceWords = WordTokenizer.tokenize(sentence).compactMap(\.word)
            guard sentenceWords.count >= 3 else { return false }
            return sentenceWords.contains { token in
                candidates.contains(token.lowercased())
            }
        }
    }
}

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

/// 词典例句翻译能力由组合根注入，DictKit 不直接依赖具体 LLM 服务。
public struct DictExampleTranslationActions: Sendable {
    private let translateAction: @Sendable (String) async -> String?

    public init(translate: @escaping @Sendable (String) async -> String?) {
        self.translateAction = translate
    }

    func translate(_ sentence: String) async -> String? {
        let source = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty,
              let translated = await translateAction(source)?.trimmingCharacters(
                  in: .whitespacesAndNewlines
              ),
              !translated.isEmpty
        else { return nil }
        return translated
    }
}

actor DictExampleTranslationCache {
    static let shared = DictExampleTranslationCache()

    private var translations: [String: String] = [:]
    private var inFlight: [String: Task<String?, Never>] = [:]

    func translation(
        for sentence: String,
        using actions: DictExampleTranslationActions
    ) async -> String? {
        let key = DictDisplayText.normalizedWhitespace(sentence).lowercased()
        guard !key.isEmpty else { return nil }
        if let cached = translations[key] {
            return cached
        }
        if let pending = inFlight[key] {
            return await pending.value
        }

        let task = Task { await actions.translate(sentence) }
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
    var definitionText: String {
        senses
            .map { DictDisplayText.normalizedWhitespace($0.definition) }
            .joined(separator: "; ")
    }
    var synonymText: String? {
        var seen = Set<String>()
        let synonyms = senses
            .flatMap(\.synonyms)
            .filter { seen.insert($0.lowercased()).inserted }
            .prefix(6)
        return synonyms.isEmpty ? nil : "≈ \(synonyms.joined(separator: " · "))"
    }
}

struct DictFallbackDefinitionDisplayGroup: Identifiable, Equatable {
    let partOfSpeechLabel: String
    let definitions: [String]

    var id: String { "\(partOfSpeechLabel)-\(definitions.joined())" }
    var definitionText: String {
        definitions
            .map(DictDisplayText.normalizedWhitespace)
            .joined(separator: "; ")
    }
}

struct DictUsageExample: Identifiable, Equatable {
    let partOfSpeechLabel: String
    let partOfSpeechAbbreviation: String
    let meaning: String?
    let text: String

    var id: String { "\(partOfSpeechAbbreviation)-\(text)" }
    var annotation: String {
        guard let meaning, !meaning.isEmpty else {
            return "（\(partOfSpeechAbbreviation)）"
        }
        return "（\(partOfSpeechAbbreviation) \(meaning)）"
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
        let meaning: String?
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
                    meaning: descriptor.meaning,
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
            meaning: conciseMeaning(matchingMeaning?.meaning)
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
            meaning: conciseMeaning(meaningGroup.meaning)
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
            meaning: DictDisplayText.normalizedWhitespace(sense.definition)
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
            meaning: nil
        )
    }

    private static func conciseMeaning(_ meaning: String?) -> String? {
        guard let meaning else { return nil }
        let components = meaning.components(separatedBy: CharacterSet(charactersIn: ",，;；"))
        return components
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
            ?? meaning.trimmingCharacters(in: .whitespacesAndNewlines)
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

/// 词典浮窗卡片：释义/音标/考试标签/语法点，卡内词与 related 可继续点击跳转。
public struct DictCardView: View {
    private let phraseCandidates: [String]
    private let dictionary: DictDatabase
    private let grammar: GrammarPointStore
    private let contextText: String?
    private let onSpeak: (@MainActor (String) -> Void)?
    private let favoriteActions: WordFavoriteActions?
    private let aiFallback: (@Sendable (String) async -> String?)?
    private let exampleTranslationActions: DictExampleTranslationActions
    private let onDismiss: (@MainActor () -> Void)?

    @State private var path: [DictTarget]
    @State private var entry: DictEntry?
    @State private var contextualPhrases: [DictEntry] = []
    @State private var isLoading = true
    @State private var aiExplanation: String?
    @State private var isLoadingAI = false
    @State private var isFavorite = false
    @State private var isUpdatingFavorite = false
    @State private var isEnglishExpanded = false
    @State private var exampleTranslations: [String: String] = [:]
    @State private var translatingExampleIDs: Set<String> = []
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        target: DictTarget,
        phraseCandidates: [String] = [],
        contextText: String? = nil,
        dictionary: DictDatabase,
        grammar: GrammarPointStore,
        onSpeak: (@MainActor (String) -> Void)? = nil,
        favoriteActions: WordFavoriteActions? = nil,
        aiFallback: (@Sendable (String) async -> String?)? = nil,
        exampleTranslationActions: DictExampleTranslationActions,
        onDismiss: (@MainActor () -> Void)? = nil
    ) {
        _path = State(initialValue: [target])
        self.phraseCandidates = phraseCandidates
        self.contextText = contextText
        self.dictionary = dictionary
        self.grammar = grammar
        self.onSpeak = onSpeak
        self.favoriteActions = favoriteActions
        self.aiFallback = aiFallback
        self.exampleTranslationActions = exampleTranslationActions
        self.onDismiss = onDismiss
    }

    private var currentTarget: DictTarget? { path.last }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: DictCardLayout.contentSpacing) {
                    content
                }
                .padding(DictCardLayout.contentPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        }
        .frame(width: DictCardLayout.width)
        .frame(maxHeight: DictCardLayout.maximumHeight)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            reduceTransparency
                ? AnyShapeStyle(Color.dsSurface)
                : AnyShapeStyle(.regularMaterial),
            in: RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
                .stroke(Color.dsBorder, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
        .task(id: path) {
            await loadCurrentTarget()
        }
        .accessibilityAction(named: "关闭释义") {
            onDismiss?()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            if path.count > 1 {
                Button {
                    _ = path.popLast()
                } label: {
                    Image(systemName: "chevron.backward")
                }
                .buttonStyle(.borderless)
            }
            switch currentTarget {
            case .word(let word):
                Text(entry?.word ?? word)
                    .font(.title3.weight(.bold))
                    .lineLimit(1)
                    .layoutPriority(1)
                if let phonetic = entry?.phonetic {
                    Text("/\(phonetic)/")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                wordActions(word)
            case .grammarPoint(let id):
                Text(grammar.point(id: id)?.title ?? "语法点")
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 4)
                dismissButton
            case nil:
                EmptyView()
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func wordActions(_ word: String) -> some View {
        HStack(spacing: 0) {
            if let onSpeak {
                Button {
                    onSpeak(entry?.word ?? word)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.dsSky)
                .accessibilityLabel("播放读音")
            }
            if favoriteActions != nil {
                Button {
                    toggleFavorite(word)
                } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(isFavorite ? Color.dsSunset : Color.secondary)
                .disabled(isUpdatingFavorite)
                .accessibilityLabel(isFavorite ? "取消收藏单词" : "收藏单词")
                .accessibilityAddTraits(isFavorite ? .isSelected : [])
            } else {
                dismissButton
            }
        }
    }

    @ViewBuilder
    private var dismissButton: some View {
        if let onDismiss {
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭释义")
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch currentTarget {
        case .word(let word):
            wordContent(word)
        case .grammarPoint(let id):
            if let point = grammar.point(id: id) {
                grammarContent(point)
            } else {
                Text("未找到该语法点")
                    .foregroundStyle(.secondary)
            }
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder
    private func wordContent(_ word: String) -> some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity)
        } else if let entry {
            if !entry.tags.isEmpty || entry.oxford || entry.collins > 0 {
                tagChips(entry)
            }
            if entry.meaningGroups.isEmpty {
                missingChineseMeaning(entry.word)
            } else {
                chineseMeaningSection(entry)
            }
            if !entry.senses.isEmpty || !entry.fallbackEnglishDefinitions.isEmpty {
                englishDisclosureSection(entry)
            }
            if path.count == 1, !contextualPhrases.isEmpty {
                contextualPhraseSection(contextualPhrases)
            }
            usageExampleSection(entry, requestedWord: word)
            if !entry.wordForms.isEmpty {
                wordFormsSection(entry)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Label("词典未收录该词", systemImage: "book.closed")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                if let aiExplanation {
                    Text(aiExplanation)
                        .font(.subheadline)
                    Text("AI 生成，仅供参考（非词典权威）")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if aiFallback != nil {
                    Button {
                        requestAIExplanation(word)
                    } label: {
                        if isLoadingAI {
                            ProgressView()
                        } else {
                            Label("用 AI 简单解释", systemImage: "sparkles")
                        }
                    }
                    .buttonStyle(.dsAction(.tinted(.dsSky), fullWidth: false, compact: true))
                    .disabled(isLoadingAI)
                }
            }
        }
    }

    private func contextualPhraseSection(_ phrases: [DictEntry]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            compactSectionTitle("短语")
            ForEach(phrases, id: \.word) { phrase in
                Button {
                    path.append(.word(phrase.word))
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(phrase.word)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.dsSkyDeep)
                        if let meaning = phrase.meaningGroups.first?.meaning {
                            Text(meaning)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func chineseMeaningSection(_ entry: DictEntry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(entry.meaningGroups) { group in
                HStack(alignment: .firstTextBaseline, spacing: DictCardLayout.definitionColumnSpacing) {
                    partOfSpeechText(group.partOfSpeech ?? "")
                    Text(group.meaning)
                        .font(.subheadline)
                        .lineSpacing(1)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func englishDisclosureSection(_ entry: DictEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    isEnglishExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Label(
                        isEnglishExpanded ? "收起英文释义" : "查看英文释义",
                        systemImage: "character.book.closed"
                    )
                    .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(isEnglishExpanded ? 180 : 0))
                }
                .frame(minHeight: 34)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.dsSkyDeep)
            .accessibilityValue(isEnglishExpanded ? "已展开" : "已折叠")

            if isEnglishExpanded {
                englishSenseContent(entry)
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private func englishSenseContent(_ entry: DictEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !entry.senses.isEmpty {
                let senseGroups = DictSenseDisplayPolicy.groups(for: entry.senses)
                ForEach(senseGroups) { group in
                    HStack(alignment: .firstTextBaseline, spacing: DictCardLayout.definitionColumnSpacing) {
                        englishPartOfSpeechText(group.partOfSpeechLabel)
                        VStack(alignment: .leading, spacing: 3) {
                            tappableDictionaryText(
                                group.definitionText,
                                contextID: "dict-\(entry.word)-sense-\(group.id)"
                            )
                                .lineSpacing(1)
                                .fixedSize(horizontal: false, vertical: true)
                            if let synonyms = group.synonymText {
                                tappableDictionaryText(
                                    synonyms,
                                    contextID: "dict-\(entry.word)-synonyms-\(group.id)"
                                )
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .font(.subheadline)
                    }
                }
            } else {
                let fallbackGroups = DictSenseDisplayPolicy.fallbackGroups(
                    for: entry.fallbackEnglishDefinitions
                )
                ForEach(fallbackGroups) { group in
                    HStack(alignment: .firstTextBaseline, spacing: DictCardLayout.definitionColumnSpacing) {
                        englishPartOfSpeechText(group.partOfSpeechLabel)
                        tappableDictionaryText(
                            group.definitionText,
                            contextID: "dict-\(entry.word)-fallback-\(group.id)"
                        )
                        .font(.subheadline)
                        .lineSpacing(1)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func tappableDictionaryText(_ text: String, contextID: String) -> some View {
        TappableText(
            tokens: TokenCache.tokens(for: text, cacheKey: contextID),
            contextID: contextID,
            onSelect: navigateToSelectedWord
        )
    }

    private func tappableExampleText(
        _ example: DictUsageExample,
        contextID: String
    ) -> some View {
        var tokens = TokenCache.tokens(for: example.text, cacheKey: contextID)
        tokens.append(
            TextToken(
                id: tokens.count,
                display: example.annotation,
                word: nil
            )
        )
        return TappableText(
            tokens: tokens,
            contextID: contextID,
            onSelect: navigateToSelectedWord
        )
    }

    private func navigateToSelectedWord(_ selection: TokenSelection) {
        if case .word(let currentWord) = currentTarget,
           currentWord.caseInsensitiveCompare(selection.word) == .orderedSame {
            return
        }
        path.append(.word(selection.word))
    }

    private func englishPartOfSpeechText(_ label: String) -> some View {
        Text(label)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.dsSunset)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: DictCardLayout.partOfSpeechColumnWidth, alignment: .leading)
    }

    @ViewBuilder
    private func usageExampleSection(_ entry: DictEntry, requestedWord: String) -> some View {
        let groups = DictUsageExamplePolicy.groups(
            for: entry,
            requestedWord: requestedWord,
            contextText: contextText
        )
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Divider()
                compactSectionTitle("例句")
                ForEach(groups) { group in
                    HStack(
                        alignment: .firstTextBaseline,
                        spacing: DictCardLayout.definitionColumnSpacing
                    ) {
                        englishPartOfSpeechText(group.partOfSpeechLabel)
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(group.examples.enumerated()), id: \.element.id) { index, example in
                                VStack(alignment: .leading, spacing: 2) {
                                    tappableExampleText(
                                        example,
                                        contextID: "dict-\(entry.word)-usage-\(group.id)-\(index)"
                                    )
                                    .font(.subheadline)
                                    .lineSpacing(1)
                                    exampleTranslationText(example)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder
    private func exampleTranslationText(_ example: DictUsageExample) -> some View {
        if let translation = exampleTranslations[example.id] {
            Text(translation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("中文翻译：\(translation)")
        } else if translatingExampleIDs.contains(example.id) {
            HStack(spacing: 5) {
                ProgressView()
                    .controlSize(.mini)
                Text("正在翻译…")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .accessibilityElement(children: .combine)
        } else {
            Button("翻译暂不可用，点击重试") {
                translateExample(example)
            }
            .font(.caption2)
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private func partOfSpeechText(_ text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.dsSkyDeep)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(width: DictCardLayout.partOfSpeechColumnWidth, alignment: .leading)
    }

    private func wordFormsSection(_ entry: DictEntry) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Divider()
            compactSectionTitle("词形")
            FlowLayout(spacing: 6) {
                ForEach(Array(entry.wordForms.prefix(8))) { form in
                    Button {
                        path.append(.word(form.word))
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(form.label)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.primary.opacity(0.72))
                            Text(form.word)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.dsSkyDeep)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.dsSky.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func missingChineseMeaning(_ word: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("本地库暂无中文释义", systemImage: "character.book.closed")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let aiExplanation {
                Text(aiExplanation)
                    .font(.subheadline)
                Text("AI 生成，仅供参考（非本地词典内容）")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if aiFallback != nil {
                Button {
                    requestAIExplanation(word)
                } label: {
                    if isLoadingAI {
                        ProgressView()
                    } else {
                        Label("临时生成中文解释", systemImage: "sparkles")
                    }
                }
                .buttonStyle(.dsAction(.tinted(.dsSky), fullWidth: false, compact: true))
                .disabled(isLoadingAI)
            }
        }
    }

    private func compactSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
    }

    @ViewBuilder
    private func tagChips(_ entry: DictEntry) -> some View {
        let titles = DictTagDisplayPolicy.orderedTitles(for: entry)
        if !titles.isEmpty {
            ViewThatFits(in: .horizontal) {
                ForEach(Array(stride(from: titles.count, through: 1, by: -1)), id: \.self) { count in
                    HStack(spacing: 6) {
                        ForEach(titles.prefix(count), id: \.self) { title in
                            chip(title)
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func chip(_ text: String) -> some View {
        DSChip(text, tint: .dsSky)
    }

    @ViewBuilder
    private func grammarContent(_ point: GrammarPoint) -> some View {
        Text(point.explanationZh)
            .font(.subheadline)
        ForEach(Array(point.examples.enumerated()), id: \.offset) { _, example in
            VStack(alignment: .leading, spacing: 2) {
                // 例句内的词可继续点击跳转
                TappableText(
                    tokens: WordTokenizer.tokenize(example.en),
                    contextID: "example-\(point.id)",
                    onSelect: { selection in
                        path.append(.word(selection.word))
                    }
                )
                .font(.footnote)
                Text(example.zh)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.dsBubbleIncoming, in: RoundedRectangle(cornerRadius: DSRadius.inline))
        }
        if !point.related.isEmpty {
            HStack(spacing: 8) {
                Text("相关：")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(point.related, id: \.self) { relatedID in
                    if let related = grammar.point(id: relatedID) {
                        Button(related.title) {
                            path.append(.grammarPoint(relatedID))
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    // MARK: - 加载

    private func loadCurrentTarget() async {
        guard case .word(let word) = currentTarget else {
            isLoading = false
            return
        }
        isLoading = true
        isFavorite = false
        isUpdatingFavorite = false
        isEnglishExpanded = false
        aiExplanation = nil
        contextualPhrases = []
        exampleTranslations = [:]
        translatingExampleIDs = []
        let loadedEntry = await dictionary.lookup(word)
        if path.count == 1 {
            contextualPhrases = await dictionary.matchingPhrases(
                phraseCandidates,
                excluding: word,
                limit: 2
            )
        }
        entry = loadedEntry
        let resolvedWord = loadedEntry?.word ?? word
        isFavorite = await favoriteActions?.contains(resolvedWord) ?? false
        isLoading = false
        if let loadedEntry {
            await translateUsageExamples(for: loadedEntry, requestedWord: word)
        }
    }

    private func translateUsageExamples(
        for entry: DictEntry,
        requestedWord: String
    ) async {
        let examples = DictUsageExamplePolicy.groups(
            for: entry,
            requestedWord: requestedWord,
            contextText: contextText
        )
        .flatMap(\.examples)
        guard !examples.isEmpty else { return }

        translatingExampleIDs = Set(examples.map(\.id))
        await withTaskGroup(of: (String, String?).self) { group in
            for example in examples {
                group.addTask {
                    let translated = await DictExampleTranslationCache.shared.translation(
                        for: example.text,
                        using: exampleTranslationActions
                    )
                    return (example.id, translated)
                }
            }
            for await (id, translation) in group {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    return
                }
                translatingExampleIDs.remove(id)
                if let translation {
                    exampleTranslations[id] = translation
                }
            }
        }
    }

    private func translateExample(_ example: DictUsageExample) {
        guard !translatingExampleIDs.contains(example.id) else { return }
        translatingExampleIDs.insert(example.id)
        Task {
            let translated = await DictExampleTranslationCache.shared.translation(
                for: example.text,
                using: exampleTranslationActions
            )
            translatingExampleIDs.remove(example.id)
            if let translated {
                exampleTranslations[example.id] = translated
            }
        }
    }

    private func toggleFavorite(_ word: String) {
        guard let favoriteActions, !isUpdatingFavorite else { return }
        isUpdatingFavorite = true
        Haptics.selection()
        let resolvedWord = entry?.word ?? word
        let translation = entry?.translationLines.joined(separator: "；") ?? aiExplanation
        Task {
            isFavorite = await favoriteActions.toggle(
                resolvedWord,
                translationZh: translation
            )
            isUpdatingFavorite = false
        }
    }

    private func requestAIExplanation(_ word: String) {
        guard let aiFallback else { return }
        isLoadingAI = true
        Task {
            aiExplanation = await aiFallback(word) ?? "解释失败，请稍后再试"
            isLoadingAI = false
        }
    }
}

import CoreKit
import DesignSystem
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

/// 词典浮窗卡片：释义/音标/考试标签/语法点，卡内词与 related 可继续点击跳转。
public struct DictCardView: View {
    private let contextSentence: String?
    private let phraseCandidates: [String]
    private let dictionary: DictDatabase
    private let grammar: GrammarPointStore
    private let onSpeak: (@MainActor (String) -> Void)?
    private let favoriteActions: WordFavoriteActions?
    private let aiFallback: (@Sendable (String) async -> String?)?
    private let onDismiss: (@MainActor () -> Void)?

    @State private var path: [DictTarget]
    @State private var entry: DictEntry?
    @State private var contextualPhrases: [DictEntry] = []
    @State private var grammarPoints: [GrammarPoint] = []
    @State private var isLoading = true
    @State private var aiExplanation: String?
    @State private var isLoadingAI = false
    @State private var isFavorite = false
    @State private var isUpdatingFavorite = false
    @State private var showsAllSenses = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(
        target: DictTarget,
        contextSentence: String? = nil,
        phraseCandidates: [String] = [],
        dictionary: DictDatabase,
        grammar: GrammarPointStore,
        onSpeak: (@MainActor (String) -> Void)? = nil,
        favoriteActions: WordFavoriteActions? = nil,
        aiFallback: (@Sendable (String) async -> String?)? = nil,
        onDismiss: (@MainActor () -> Void)? = nil
    ) {
        _path = State(initialValue: [target])
        self.contextSentence = contextSentence
        self.phraseCandidates = phraseCandidates
        self.dictionary = dictionary
        self.grammar = grammar
        self.onSpeak = onSpeak
        self.favoriteActions = favoriteActions
        self.aiFallback = aiFallback
        self.onDismiss = onDismiss
    }

    private var currentTarget: DictTarget? { path.last }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    content
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 320)
        .frame(maxHeight: 380)
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
                    .font(.headline)
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
            if path.count == 1,
               let contextSentence,
               contextSentence.localizedCaseInsensitiveCompare(word) != .orderedSame
            {
                contextSection(contextSentence)
            }
            if path.count == 1, !contextualPhrases.isEmpty {
                contextualPhraseSection(contextualPhrases)
            }
            if entry.meaningGroups.isEmpty {
                missingChineseMeaning(entry.word)
            } else {
                chineseMeaningSection(entry)
            }
            if !entry.senses.isEmpty || !entry.fallbackEnglishDefinitions.isEmpty {
                englishSenseSection(entry)
            }
            if !entry.wordForms.isEmpty {
                wordFormsSection(entry)
            }
            let points = grammarPointsToShow(for: entry.word)
            if !points.isEmpty {
                Divider()
                ForEach(points) { point in
                    grammarSummary(point)
                }
            }
            Text("本地词典 · ECDICT / WordNet")
                .font(.caption2)
                .foregroundStyle(.tertiary)
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

    private func contextSection(_ sentence: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            sectionTitle("原句语境", systemImage: "text.quote")
            Text(sentence)
                .font(.footnote)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsBubbleIncoming, in: RoundedRectangle(cornerRadius: DSRadius.inline))
    }

    private func contextualPhraseSection(_ phrases: [DictEntry]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("原句中的相关短语", systemImage: "link")
            ForEach(phrases, id: \.word) { phrase in
                Button {
                    path.append(.word(phrase.word))
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(phrase.word)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.dsSkyDeep)
                        if let meaning = phrase.meaningGroups.first?.meaning {
                            Text(meaning)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.forward")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func chineseMeaningSection(_ entry: DictEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("中文释义", systemImage: "character.book.closed")
            ForEach(entry.meaningGroups) { group in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let partOfSpeech = group.partOfSpeech {
                        Text(partOfSpeech)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.dsSkyDeep)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.dsSky.opacity(0.12), in: Capsule())
                    }
                    Text(group.meaning)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func englishSenseSection(_ entry: DictEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            sectionTitle("英文分义与例句", systemImage: "book.pages")
            if !entry.senses.isEmpty {
                let visibleSenses = showsAllSenses
                    ? entry.senses
                    : Array(entry.senses.prefix(4))
                ForEach(visibleSenses) { sense in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(sense.partOfSpeechLabel)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(sense.definition)
                                .font(.footnote)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let example = sense.examples.first {
                            Text("例：\(example)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !sense.synonyms.isEmpty {
                            Text("近义：\(sense.synonyms.prefix(4).joined(separator: " · "))")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(2)
                        }
                    }
                }
                if entry.senses.count > 4 {
                    Button(showsAllSenses ? "收起其它义项" : "查看其它 \(entry.senses.count - 4) 个义项") {
                        showsAllSenses.toggle()
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderless)
                }
            } else {
                ForEach(entry.fallbackEnglishDefinitions.prefix(4), id: \.self) { definition in
                    Text(definition)
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func wordFormsSection(_ entry: DictEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            sectionTitle("词形变化", systemImage: "arrow.triangle.branch")
            FlowLayout(spacing: 6) {
                ForEach(Array(entry.wordForms.prefix(10))) { form in
                    Button {
                        path.append(.word(form.word))
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(form.label)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text(form.word)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.dsSkyDeep)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
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

    private func sectionTitle(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func grammarPointsToShow(for word: String) -> [GrammarPoint] {
        grammar.points(forTrigger: word)
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
    private func grammarSummary(_ point: GrammarPoint) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(point.title)
                .font(.subheadline.weight(.semibold))
            Text(point.explanationZh)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Button("查看详情") {
                path.append(.grammarPoint(point.id))
            }
            .font(.footnote)
            .buttonStyle(.borderless)
        }
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
        aiExplanation = nil
        showsAllSenses = false
        contextualPhrases = []
        let loadedEntry = await dictionary.lookup(word)
        if path.count == 1 {
            contextualPhrases = await dictionary.matchingPhrases(
                phraseCandidates,
                excluding: word
            )
        }
        entry = loadedEntry
        grammarPoints = grammar.points(forTrigger: word)
        let resolvedWord = loadedEntry?.word ?? word
        isFavorite = await favoriteActions?.contains(resolvedWord) ?? false
        isLoading = false
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

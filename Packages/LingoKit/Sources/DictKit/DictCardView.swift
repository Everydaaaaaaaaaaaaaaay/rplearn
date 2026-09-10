import CoreKit
import DesignSystem
import SwiftUI
import Translation

/// 词典浮窗卡片：释义/音标/考试标签/语法点，卡内词与 related 可继续点击跳转。
public struct DictCardView: View {
    private let phraseCandidates: [String]
    private let dictionary: DictDatabase
    private let grammar: GrammarPointStore
    private let onSpeak: (@MainActor (String) -> Void)?
    private let favoriteActions: WordFavoriteActions?
    private let aiFallback: (@Sendable (String) async -> String?)?
    private let exampleTranslationActions: DictExampleTranslationActions
    private let allowsSystemTranslationFallback: Bool
    private let onDismiss: (@MainActor () -> Void)?

    @State private var path: [DictTarget]
    @State private var entry: DictEntry?
    @State private var contextualPhrases: [DictEntry] = []
    @State private var relatedPhrases: [DictEntry] = []
    @State private var isLoading = true
    @State private var aiExplanation: String?
    @State private var isLoadingAI = false
    @State private var isFavorite = false
    @State private var isUpdatingFavorite = false
    @State private var isEnglishExpanded = false
    @State private var exampleTranslations: [String: DictExampleTranslation] = [:]
    @State private var translatingExampleIDs: Set<String> = []
    @State private var appleTranslator = DictExampleAppleTranslator()
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        target: DictTarget,
        phraseCandidates: [String] = [],
        dictionary: DictDatabase,
        grammar: GrammarPointStore,
        onSpeak: (@MainActor (String) -> Void)? = nil,
        favoriteActions: WordFavoriteActions? = nil,
        aiFallback: (@Sendable (String) async -> String?)? = nil,
        exampleTranslationActions: DictExampleTranslationActions,
        allowsSystemTranslationFallback: Bool = true,
        onDismiss: (@MainActor () -> Void)? = nil
    ) {
        _path = State(initialValue: [target])
        self.phraseCandidates = phraseCandidates
        self.dictionary = dictionary
        self.grammar = grammar
        self.onSpeak = onSpeak
        self.favoriteActions = favoriteActions
        self.aiFallback = aiFallback
        self.exampleTranslationActions = exampleTranslationActions
        self.allowsSystemTranslationFallback = allowsSystemTranslationFallback
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
                .frame(
                    width: DictCardLayout.width,
                    alignment: .leading
                )
            }
            .frame(width: DictCardLayout.width)
            .scrollIndicators(.visible)
            .id(currentTarget)
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
        .translationTask(appleTranslator.configuration) { @Sendable session in
            let batch = await appleTranslator.takeBatch()
            do {
                try await session.prepareTranslation()
                for item in batch {
                    let sentenceZhHans = try? await session.translate(item.text).targetText
                    await appleTranslator.complete(item.id, with: sentenceZhHans)
                }
            } catch {
                for item in batch { await appleTranslator.complete(item.id, with: nil) }
            }
            await appleTranslator.finishBatch()
        }
        .onDisappear { appleTranslator.cancelAll() }
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
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("返回上一条释义")
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
            case .grammarTerm(let term):
                Text(term)
                    .font(.headline)
                    .lineLimit(1)
                Text("语法术语")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.dsCoach)
                Spacer(minLength: 4)
                dismissButton
            case nil:
                EmptyView()
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
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
        case .grammarTerm(let term):
            if let entry = GrammarTermCatalog.entry(for: term) {
                grammarTermContent(entry)
            } else {
                Text("未找到该语法术语")
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
            if !contextualPhrases.isEmpty || !relatedPhrases.isEmpty {
                phraseSection(
                    contextual: path.count == 1 ? contextualPhrases : [],
                    related: relatedPhrases
                )
            }
            usageExampleSection(entry)
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

    private func phraseSection(
        contextual: [DictEntry],
        related: [DictEntry]
    ) -> some View {
        let phrases = Array(
            DictPhraseDisplayPolicy.deduplicated(contextual + related).prefix(4)
        )
        return HStack(alignment: .firstTextBaseline, spacing: DictCardLayout.definitionColumnSpacing) {
            Text("短语")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.dsQuiz)
                .lineLimit(1)
                .frame(width: DictCardLayout.partOfSpeechColumnWidth, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(phrases, id: \.word) { phrase in
                    Button {
                        path.append(.word(phrase.word))
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(phrase.word)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            if let meaning = phrase.meaningGroups.first?.meaning {
                                Text(meaning)
                                    .font(.subheadline)
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                            definitionLines(
                                group.definitionLines,
                                contextID: "dict-\(entry.word)-sense-\(group.id)"
                            )
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
                        definitionLines(
                            group.definitionLines,
                            contextID: "dict-\(entry.word)-fallback-\(group.id)"
                        )
                    }
                }
            }
        }
    }

    private func definitionLines(_ lines: [String], contextID: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                tappableDictionaryText(
                    line + (index < lines.count - 1 ? ";" : ""),
                    contextID: "\(contextID)-\(index)"
                )
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.subheadline)
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
        contextID: String,
        contextualMeaningZhHans: String? = nil
    ) -> some View {
        var tokens = TokenCache.tokens(for: example.text, cacheKey: contextID)
        tokens.append(
            TextToken(
                id: tokens.count,
                display: " \(example.annotation(meaningZh: contextualMeaningZhHans))",
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
    private func usageExampleSection(_ entry: DictEntry) -> some View {
        let groups = DictUsageExamplePolicy.groups(
            for: entry
        )
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Divider()
                ForEach(groups) { group in
                    HStack(
                        alignment: .firstTextBaseline,
                        spacing: DictCardLayout.definitionColumnSpacing
                    ) {
                        englishPartOfSpeechText("例句")
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(group.examples.enumerated()), id: \.element.id) { index, example in
                                VStack(alignment: .leading, spacing: 2) {
                                    tappableExampleText(
                                        example,
                                        contextID: "dict-\(entry.word)-usage-\(group.id)-\(index)",
                                        contextualMeaningZhHans: exampleTranslations[example.id]?
                                            .contextualMeaningZhHans
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
            Text(translation.sentenceZhHans)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.primary.opacity(0.62))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("中文翻译：\(translation.sentenceZhHans)")
        } else if translatingExampleIDs.contains(example.id) {
            HStack(spacing: 5) {
                ProgressView()
                    .controlSize(.mini)
                Text("中文翻译：加载中…")
            }
            .font(.caption)
            .foregroundStyle(Color.primary.opacity(0.62))
            .accessibilityElement(children: .combine)
        } else {
            Button("翻译暂不可用，点击重试") {
                translateExample(example)
            }
            .font(.caption2)
            .buttonStyle(.plain)
            .foregroundStyle(Color.primary.opacity(0.62))
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
            FlowLayout(spacing: 6, lineSpacing: 5) {
                ForEach(titles, id: \.self) { title in
                    chip(title)
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

    private func grammarTermContent(_ entry: GrammarTermEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            grammarTermSection(title: "定义", text: entry.definition)
            Divider()
            grammarTermSection(title: "用法", text: entry.usage)
            if !entry.commonForms.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    compactSectionTitle("常见形式")
                    FlowLayout(spacing: 6, lineSpacing: 5) {
                        ForEach(entry.commonForms, id: \.self) { form in
                            grammarLinkedText(form)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 6)
                                .background(
                                    Color.dsSky.opacity(0.1),
                                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                                )
                        }
                    }
                }
            }
            if !entry.examples.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    compactSectionTitle("例句")
                    ForEach(Array(entry.examples.enumerated()), id: \.offset) { _, example in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(highlightedExample(example))
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(example.chinese)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            Color.dsBubbleIncoming,
                            in: RoundedRectangle(cornerRadius: DSRadius.inline, style: .continuous)
                        )
                    }
                }
            }
        }
    }

    private func grammarTermSection(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            compactSectionTitle(title)
            grammarLinkedText(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Native inline links preserve normal wrapping and VoiceOver link actions.
    private func grammarLinkedText(_ text: String) -> some View {
        var attributed = AttributedString()
        for segment in GrammarTermCatalog.segments(in: text) {
            switch segment {
            case .text(let value):
                attributed.append(AttributedString(value))
            case .term(let term):
                var link = AttributedString(term)
                if currentTarget != .grammarTerm(term) {
                    var url = URLComponents()
                    url.scheme = "lingotrip-grammar"
                    url.host = "term"
                    url.queryItems = [URLQueryItem(name: "name", value: term)]
                    link.link = url.url
                    link.underlineStyle = .single
                }
                attributed.append(link)
            }
        }
        return Text(attributed)
            .tint(Color.dsSkyDeep)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "lingotrip-grammar",
                      let term = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                        .queryItems?.first(where: { $0.name == "name" })?.value,
                      GrammarTermCatalog.entry(for: term) != nil else { return .discarded }
                if currentTarget != .grammarTerm(term) {
                    path.append(.grammarTerm(term))
                }
                return .handled
            })
    }

    private func highlightedExample(_ example: GrammarTermExample) -> AttributedString {
        var attributed = AttributedString(example.english)
        for highlight in example.highlights where !highlight.isEmpty {
            var searchRange = attributed.startIndex..<attributed.endIndex
            while let range = attributed[searchRange].range(of: highlight) {
                attributed[range].foregroundColor = Color.dsCoach
                attributed[range].font = .system(.subheadline, design: .rounded, weight: .bold)
                attributed[range].backgroundColor = Color.dsCoach.opacity(0.14)
                searchRange = range.upperBound..<attributed.endIndex
            }
        }
        return attributed
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
        relatedPhrases = []
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
        relatedPhrases = await dictionary.relatedPhrases(
            for: loadedEntry?.word ?? word,
            limit: 4
        )
        entry = loadedEntry
        let resolvedWord = loadedEntry?.word ?? word
        isFavorite = await favoriteActions?.contains(resolvedWord) ?? false
        isLoading = false
        if let loadedEntry {
            await translateUsageExamples(for: loadedEntry)
        }
    }

    private func translateUsageExamples(
        for entry: DictEntry
    ) async {
        let examples = DictUsageExamplePolicy.groups(
            for: entry
        )
        .flatMap(\.examples)
        guard !examples.isEmpty else { return }

        let translationActions = effectiveTranslationActions
        translatingExampleIDs = Set(examples.map(\.id))
        await withTaskGroup(of: (String, DictExampleTranslation?).self) { group in
            for example in examples {
                group.addTask {
                    let translated = await DictExampleTranslationCache.shared.translation(
                        for: example.translationRequest,
                        using: translationActions
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

    private var effectiveTranslationActions: DictExampleTranslationActions {
        translationActions(allowsDownload: false)
    }

    private func translationActions(allowsDownload: Bool) -> DictExampleTranslationActions {
        guard allowsSystemTranslationFallback else { return exampleTranslationActions }
        return exampleTranslationActions.fallingBackToSentenceTranslation { [appleTranslator] sentence in
            await appleTranslator.translate(sentence, allowsDownload: allowsDownload)
        }
    }

    private func translateExample(_ example: DictUsageExample) {
        guard !translatingExampleIDs.contains(example.id) else { return }
        // This is an explicit Retry tap: language preparation/download may now ask
        // for permission. Passive lookup and pronunciation never request downloads.
        let translationActions = translationActions(allowsDownload: true)
        translatingExampleIDs.insert(example.id)
        Task {
            let translated = await DictExampleTranslationCache.shared.translation(
                for: example.translationRequest,
                using: translationActions
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

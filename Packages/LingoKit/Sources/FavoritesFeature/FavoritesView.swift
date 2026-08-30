import CoreKit
import DesignSystem
import DictKit
import PersistenceKit
import SpeechKit
import SwiftUI

/// FavoritesFeature 所需依赖。
public struct FavoritesDependencies: Sendable {
    public let favorites: FavoritesStore
    public let dictionary: DictDatabase
    public let grammarPoints: GrammarPointStore
    public let speech: any SpeechService
    public let exampleTranslationActions: DictExampleTranslationActions

    public init(
        favorites: FavoritesStore,
        dictionary: DictDatabase,
        grammarPoints: GrammarPointStore,
        speech: any SpeechService,
        exampleTranslationActions: DictExampleTranslationActions
    ) {
        self.favorites = favorites
        self.dictionary = dictionary
        self.grammarPoints = grammarPoints
        self.speech = speech
        self.exampleTranslationActions = exampleTranslationActions
    }
}

/// 收藏夹：按单词、语法点和旧版句子分组展示。
public struct FavoritesView: View {
    private enum Filter: String, CaseIterable, Identifiable {
        case all = "全部"
        case word = "单词"
        case grammar = "语法"
        case sentence = "句子"

        var id: Self { self }
    }

    private static let partOfSpeechColumnWidth: CGFloat = 92

    private let deps: FavoritesDependencies
    @State private var favorites: [FavoriteDTO] = []
    @State private var wordEntries: [UUID: DictEntry] = [:]
    @State private var wordSelection: TokenSelection?
    @State private var isLoading = true
    @State private var filter: Filter = .all
    @State private var searchText = ""

    public init(deps: FavoritesDependencies) {
        self.deps = deps
    }

    public var body: some View {
        ZStack {
            DSWorkbenchBackdrop(focus: .favorites)

            VStack(spacing: 0) {
                filterPanel
                    .padding(.horizontal, DSSpacing.lg)
                    .padding(.top, DSSpacing.sm)
                    .padding(.bottom, DSSpacing.xs)

                if isLoading {
                    Spacer()
                    ProgressView()
                        .tint(Color.dsTravelNavy)
                    Spacer()
                } else if favorites.isEmpty {
                    emptyNotebook
                } else if filteredFavorites.isEmpty {
                    noResultsPanel
                } else {
                    List {
                        if !wordFavorites.isEmpty {
                            Section {
                                ForEach(wordFavorites) { favorite in
                                    favoritePanel { wordRow(favorite) }
                                }
                                .onDelete { indexSet in
                                    Task { await remove(at: indexSet, from: wordFavorites) }
                                }
                            } header: {
                                sectionHeader("单词", count: wordFavorites.count)
                            }
                        }

                        if !grammarFavorites.isEmpty {
                            Section {
                                ForEach(grammarFavorites) { favorite in
                                    favoritePanel { grammarRow(favorite) }
                                }
                                .onDelete { indexSet in
                                    Task { await remove(at: indexSet, from: grammarFavorites) }
                                }
                            } header: {
                                sectionHeader("语法", count: grammarFavorites.count)
                            }
                        }

                        if !sentenceFavorites.isEmpty {
                            Section {
                                ForEach(sentenceFavorites) { favorite in
                                    favoritePanel { sentenceRow(favorite) }
                                }
                                .onDelete { indexSet in
                                    Task { await remove(at: indexSet, from: sentenceFavorites) }
                                }
                            } header: {
                                sectionHeader("句子", count: sentenceFavorites.count)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .listSectionSpacing(DSSpacing.sm)
                    .scrollIndicators(.hidden)
                }
            }
        }
        .navigationTitle("收藏夹")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .wordLookupOverlay(
            selection: $wordSelection,
            dictionary: deps.dictionary,
            grammar: deps.grammarPoints,
            onSpeak: { word in
                let speech = deps.speech
                Task {
                    await speech.speak(
                        SpeechRequest(text: word, language: "en-US", purpose: .pronunciation)
                    )
                }
            },
            favoriteActions: wordFavoriteActions,
            exampleTranslationActions: deps.exampleTranslationActions
        )
        .onChange(of: wordSelection) { _, selection in
            if selection == nil {
                Task { await reload() }
            }
        }
        .task {
            await reload()
        }
    }

    private var filterPanel: some View {
        DSWorkbenchPanel(weight: .chrome, radius: DSRadius.hero, padding: DSSpacing.md) {
            VStack(spacing: DSSpacing.sm) {
                HStack(spacing: DSSpacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color.dsSceneTextSecondary)
                    TextField(
                        "",
                        text: $searchText,
                        prompt: Text("搜索收藏")
                            .foregroundStyle(Color.dsSceneTextSecondary)
                    )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundStyle(Color.dsSceneTextPrimary)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Color.dsSceneTextTertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("清除搜索")
                    }
                }
                .frame(minHeight: 40)

                Picker("收藏类型", selection: $filter) {
                    ForEach(Filter.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var emptyNotebook: some View {
        VStack {
            Spacer(minLength: 42)
            DSWorkbenchPanel(weight: .reading, radius: 28, padding: 30) {
                VStack(spacing: DSSpacing.md) {
                    Image(systemName: "bookmark")
                        .font(.system(size: 46, weight: .light))
                        .foregroundStyle(Color.dsSkyDeep)

                    Text("还没有收藏")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.dsSceneTextPrimary)

                    Text("在对话中收藏单词、语法或句子，\n它们会整理在这里。")
                        .font(.subheadline)
                        .foregroundStyle(Color.dsSceneTextSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            }
            .rotationEffect(.degrees(-1.5))
            .frame(maxWidth: 350)
            .padding(.horizontal, 34)
            Spacer(minLength: 90)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResultsPanel: some View {
        VStack {
            Spacer()
            DSWorkbenchPanel(weight: .reading) {
                VStack(spacing: DSSpacing.sm) {
                    Image(systemName: "text.magnifyingglass")
                        .font(.largeTitle)
                        .foregroundStyle(Color.dsSkyDeep)
                    Text("没有找到相关收藏")
                        .font(.headline)
                    Text("试试其他关键词或收藏类型")
                        .font(.subheadline)
                        .foregroundStyle(Color.dsSceneTextSecondary)
                }
                .foregroundStyle(Color.dsSceneTextPrimary)
            }
            .frame(maxWidth: 340)
            .padding(.horizontal, DSSpacing.xl)
            Spacer()
        }
    }

    private func favoritePanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        DSWorkbenchPanel(weight: .reading, radius: DSRadius.card, padding: DSSpacing.md) {
            content()
        }
        .listRowInsets(
            EdgeInsets(top: 5, leading: DSSpacing.lg, bottom: 5, trailing: DSSpacing.lg)
        )
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(count)")
                .monospacedDigit()
        }
        .font(.subheadline.weight(.bold))
        .foregroundStyle(Color.dsSceneTextPrimary)
        .textCase(nil)
        .padding(.horizontal, 4)
    }

    private var filteredFavorites: [FavoriteDTO] {
        let kindFiltered = favorites.filter { favorite in
            switch filter {
            case .all: true
            case .word: favorite.kind == .word
            case .grammar: favorite.kind == .grammarPoint
            case .sentence: favorite.kind == .sentence
            }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return kindFiltered }
        return kindFiltered.filter { favorite in
            favorite.sentence.localizedCaseInsensitiveContains(query)
                || favorite.translationZh?.localizedCaseInsensitiveContains(query) == true
                || favorite.characterName.localizedCaseInsensitiveContains(query)
        }
    }

    private var wordFavorites: [FavoriteDTO] {
        filteredFavorites.filter { $0.kind == .word }
    }

    private var grammarFavorites: [FavoriteDTO] {
        filteredFavorites.filter { $0.kind == .grammarPoint }
    }

    private var sentenceFavorites: [FavoriteDTO] {
        filteredFavorites.filter { $0.kind == .sentence }
    }

    private func wordRow(_ favorite: FavoriteDTO) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    TappableText(
                        tokens: TokenCache.tokens(
                            for: favorite.sentence,
                            cacheKey: "fav-word-\(favorite.id.uuidString)"
                        ),
                        contextID: "fav-word-\(favorite.id.uuidString)",
                        selection: wordSelection,
                        onSelect: { wordSelection = $0 }
                    )
                    .font(.title3.weight(.semibold))

                    if let phonetic = wordEntries[favorite.id]?.phonetic {
                        Text("/\(phonetic)/")
                            .font(.footnote)
                            .foregroundStyle(Color.dsSceneTextSecondary)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    let groups = meaningGroups(for: favorite)
                    if groups.isEmpty {
                        Text("暂无中文释义")
                            .font(.subheadline)
                            .foregroundStyle(Color.dsSceneTextSecondary)
                    } else {
                        ForEach(groups) { group in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                partOfSpeechLabel(group)
                                Text(group.meaning)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.dsSceneTextPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                favoriteDate(favorite.createdAt)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            speechButton(text: favorite.sentence, label: "播放单词读音")
        }
        .padding(.vertical, 7)
    }

    private func partOfSpeechLabel(_ group: DictMeaningGroup) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(group.partOfSpeech ?? "释义")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.dsSkyDeep)

            if let abbreviation = group.partOfSpeechAbbreviation {
                Text(abbreviation)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.dsSceneTextSecondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(width: Self.partOfSpeechColumnWidth, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func grammarRow(_ favorite: FavoriteDTO) -> some View {
        let point = favorite.referenceID.flatMap(deps.grammarPoints.point(id:))
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "text.book.closed.fill")
                    .font(.subheadline)
                    .foregroundStyle(Color.dsSkyDeep)
                Text(point?.title ?? favorite.sentence)
                    .font(.headline)
                Spacer(minLength: 8)
                favoriteDate(favorite.createdAt)
            }

            if let explanation = point?.explanationZh ?? favorite.translationZh,
               !explanation.isEmpty {
                Text(explanation)
                    .font(.subheadline)
                    .foregroundStyle(Color.dsSceneTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let example = point?.examples.first {
                VStack(alignment: .leading, spacing: 3) {
                    Text(example.en)
                        .font(.footnote.weight(.medium))
                    Text(example.zh)
                        .font(.caption)
                        .foregroundStyle(Color.dsSceneTextSecondary)
                }
                .padding(.leading, 25)
            }
        }
        .padding(.vertical, 7)
    }

    private func sentenceRow(_ favorite: FavoriteDTO) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                TappableText(
                    tokens: TokenCache.tokens(
                        for: favorite.sentence,
                        cacheKey: "fav-sentence-\(favorite.id.uuidString)"
                    ),
                    contextID: "fav-sentence-\(favorite.id.uuidString)",
                    selection: wordSelection,
                    onSelect: { wordSelection = $0 }
                )
                .font(.body)

                if let translation = favorite.translationZh {
                    Text(translation)
                        .font(.footnote)
                        .foregroundStyle(Color.dsSceneTextSecondary)
                }

                HStack(spacing: 5) {
                    Text(favorite.characterName)
                    Text("·")
                    favoriteDate(favorite.createdAt)
                }
                .font(.caption)
                .foregroundStyle(Color.dsSceneTextTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            speechButton(text: favorite.sentence, label: "播放收藏句子")
        }
        .padding(.vertical, 7)
    }

    private func meaningGroups(for favorite: FavoriteDTO) -> [DictMeaningGroup] {
        if let groups = wordEntries[favorite.id]?.meaningGroups, !groups.isEmpty {
            return groups
        }
        return DictEntry(
            word: favorite.sentence,
            translation: favorite.translationZh
        ).meaningGroups
    }

    private func favoriteDate(_ date: Date) -> some View {
        Text(date, style: .date)
            .font(.caption)
            .foregroundStyle(Color.dsSceneTextTertiary)
    }

    private func speechButton(text: String, label: String) -> some View {
        Button {
            let speech = deps.speech
            Task { await speech.speak(text, language: "en-US") }
        } label: {
            Image(systemName: "speaker.wave.2.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.dsSky)
                .frame(width: 44, height: 44)
                .background(Color.dsSky.opacity(0.12), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
    }

    private var wordFavoriteActions: WordFavoriteActions {
        let favoritesStore = deps.favorites
        return WordFavoriteActions(
            contains: { word in
                (try? await favoritesStore.isWordFavorited(word)) ?? false
            },
            toggle: { word, translationZh in
                (try? await favoritesStore.toggleWord(word, translationZh: translationZh)) ?? false
            }
        )
    }

    private func reload() async {
        defer { isLoading = false }
        let loadedFavorites = (try? await deps.favorites.all()) ?? []
        var loadedEntries: [UUID: DictEntry] = [:]
        for favorite in loadedFavorites where favorite.kind == .word {
            if let entry = await deps.dictionary.lookup(favorite.sentence) {
                loadedEntries[favorite.id] = entry
            }
        }
        favorites = loadedFavorites
        wordEntries = loadedEntries
    }

    private func remove(at indexSet: IndexSet, from source: [FavoriteDTO]) async {
        for index in indexSet {
            guard source.indices.contains(index) else { continue }
            try? await deps.favorites.remove(id: source[index].id)
        }
        await reload()
    }
}

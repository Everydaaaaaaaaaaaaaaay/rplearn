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

    public init(
        favorites: FavoritesStore,
        dictionary: DictDatabase,
        grammarPoints: GrammarPointStore,
        speech: any SpeechService) {
        self.favorites = favorites
        self.dictionary = dictionary
        self.grammarPoints = grammarPoints
        self.speech = speech
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
    private let onBrowseConversations: @MainActor () -> Void
    @State private var favorites: [FavoriteDTO] = []
    @State private var wordEntries: [UUID: DictEntry] = [:]
    @State private var wordSelection: TokenSelection?
    @State private var isLoading = true
    @State private var filter: Filter = .all
    @State private var searchText = ""
    @State private var isSearchExpanded = false
    @FocusState private var isSearchFieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        deps: FavoritesDependencies,
        onBrowseConversations: @escaping @MainActor () -> Void = {}
    ) {
        self.deps = deps
        self.onBrowseConversations = onBrowseConversations
    }

    public var body: some View {
        VStack(spacing: 0) {
            compactControls
                .padding(.top, 6)
                .padding(.bottom, Puff.Space.xs)

            if isLoading {
                Spacer()
                PuffLoadingDots()
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
                .listSectionSpacing(Puff.Space.s)
                .scrollIndicators(.hidden)
            }
        }
        .background(Puff.Palette.page.ignoresSafeArea())
        .modifier(IOS18FavoritesKeyboardStabilityModifier())
        .navigationTitle("收藏夹")
        .navigationBarTitleDisplayMode(.inline)
        .animation(reduceMotion ? nil : Puff.Motion.bouncy, value: isSearchExpanded)
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
            favoriteActions: wordFavoriteActions)
        .onChange(of: wordSelection) { _, selection in
            if selection == nil {
                Task { await reload() }
            }
        }
        .task {
            await reload()
        }
    }

    @ViewBuilder
    private var compactControls: some View {
        if isSearchExpanded {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(PuffCandy.sky.deep)

                TextField("搜索收藏", text: $searchText)
                    .focused($isSearchFieldFocused)
                    .submitLabel(.search)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.puff(.body, .semibold))
                    .foregroundStyle(Puff.Palette.ink)

                Button(action: collapseSearch) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(Puff.Palette.inkSoft)
                        .frame(width: 32, height: 32)
                        .background(Puff.Palette.card, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.puffSquish)
                .accessibilityLabel("取消搜索")
            }
            .padding(.leading, 14)
            .padding(.trailing, 7)
            .frame(height: 46)
            .background(PuffCandy.sky.wash, in: RoundedRectangle(cornerRadius: 23, style: .continuous))
            .padding(.horizontal, Puff.Space.m)
            .transition(reduceMotion ? .opacity : .scale(scale: 0.86, anchor: .trailing).combined(with: .opacity))
        } else {
            HStack(spacing: 0) {
                PuffFilterBar(selection: $filter, options: Filter.allCases.map {
                    .init($0, title: $0.rawValue, count: $0 == .all ? nil : count(of: $0))
                }, candy: .bubblegum)

                Button(action: expandSearch) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(PuffCandy.sky.deep)
                        .frame(width: 44, height: 44)
                        .background(PuffCandy.sky.wash, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.puffSquish)
                .padding(.trailing, Puff.Space.m)
                .accessibilityLabel("搜索收藏")
            }
            .transition(reduceMotion ? .opacity : .scale(scale: 0.96, anchor: .leading).combined(with: .opacity))
        }
    }

    private func count(of filter: Filter) -> Int {
        favorites.filter { favorite in
            switch filter {
            case .all: true
            case .word: favorite.kind == .word
            case .grammar: favorite.kind == .grammarPoint
            case .sentence: favorite.kind == .sentence
            }
        }.count
    }

    private func expandSearch() {
        withAnimation(reduceMotion ? nil : Puff.Motion.bouncy) {
            isSearchExpanded = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 120))
            isSearchFieldFocused = true
        }
    }

    private func collapseSearch() {
        isSearchFieldFocused = false
        searchText = ""
        withAnimation(reduceMotion ? nil : Puff.Motion.bouncy) {
            isSearchExpanded = false
        }
    }

    private var emptyNotebook: some View {
        ScrollView {
            PuffEmptyState("还没有收藏", mood: .happy) {
                Button(action: onBrowseConversations) {
                    Label("去对话看看", systemImage: "bubble.left.and.bubble.right.fill")
                }
                .buttonStyle(PuffCandyButtonStyle(.bubblegum))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 80)
        }
    }

    private var noResultsPanel: some View {
        ScrollView {
            PuffEmptyState("没有找到相关收藏", mood: .curious)
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
        }
    }

    private func favoritePanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, Puff.Space.m)
            .padding(.vertical, Puff.Space.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .puffCard(radius: Puff.Radius.large)
            .listRowInsets(
                EdgeInsets(top: 5, leading: Puff.Space.m, bottom: 5, trailing: Puff.Space.m)
            )
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.puff(.headline, .heavy))
                .foregroundStyle(Puff.Palette.ink)
            Text("\(count)")
                .font(.puff(.caption, .heavy))
                .monospacedDigit()
                .foregroundStyle(PuffCandy.bubblegum.deep)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(PuffCandy.bubblegum.wash, in: Capsule())
            Spacer()
        }
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
                    .font(.puff(.title3, .heavy))

                    if let phonetic = wordEntries[favorite.id]?.phonetic {
                        Text("/\(phonetic)/")
                            .font(.footnote)
                            .foregroundStyle(Puff.Palette.inkSoft)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    let groups = meaningGroups(for: favorite)
                    if groups.isEmpty {
                        Text("暂无中文释义")
                            .font(.subheadline)
                            .foregroundStyle(Puff.Palette.inkSoft)
                    } else {
                        ForEach(groups) { group in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                partOfSpeechLabel(group)
                                Text(group.meaning)
                                    .font(.subheadline)
                                    .foregroundStyle(Puff.Palette.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                if favorite.sourceMessageID != nil {
                    FavoriteSourceView(favoriteID: favorite.id, store: deps.favorites)
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
                .foregroundStyle(PuffCandy.sky.deep)

            if let abbreviation = group.partOfSpeechAbbreviation {
                Text(abbreviation)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Puff.Palette.inkSoft)
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
                    .foregroundStyle(PuffCandy.sky.deep)
                Text(point?.title ?? favorite.sentence)
                    .font(.puff(.headline, .heavy))
                Spacer(minLength: 8)
                favoriteDate(favorite.createdAt)
            }

            if let explanation = point?.explanationZh ?? favorite.translationZh,
               !explanation.isEmpty {
                Text(explanation)
                    .font(.subheadline)
                    .foregroundStyle(Puff.Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let example = point?.examples.first {
                VStack(alignment: .leading, spacing: 3) {
                    Text(example.en)
                        .font(.footnote.weight(.medium))
                    Text(example.zh)
                        .font(.caption)
                        .foregroundStyle(Puff.Palette.inkSoft)
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
                        .foregroundStyle(Puff.Palette.inkSoft)
                }

                HStack(spacing: 5) {
                    Text(favorite.characterName)
                    Text("·")
                    favoriteDate(favorite.createdAt)
                }
                .font(.caption)
                .foregroundStyle(Puff.Palette.inkSoft)
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
            .foregroundStyle(Puff.Palette.inkSoft)
    }

    private func speechButton(text: String, label: String) -> some View {
        Button {
            let speech = deps.speech
            Task { await speech.speak(text, language: "en-US") }
        } label: {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(PuffCandy.sky.base, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.puffSquish)
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

/// iOS 18 会让键盘安全区参与 GeometryReader 高度计算，导致笔记本上的
/// 透视内容整体上移；iOS 26 保持系统默认键盘布局，避免改变已验收效果。
private struct IOS18FavoritesKeyboardStabilityModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if DSPlatformVisualPolicy.requiresIOS18RenderingCompensation {
            content.ignoresSafeArea(.keyboard, edges: .bottom)
        } else {
            content
        }
    }
}

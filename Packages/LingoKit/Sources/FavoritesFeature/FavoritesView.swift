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
        ZStack {
            DSWorkbenchBackdrop(focus: .favorites)

            VStack(spacing: 0) {
                compactControls
                    .padding(.horizontal, DSSpacing.lg)
                    .padding(.top, 6)
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
        .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86), value: isSearchExpanded)
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

    @ViewBuilder
    private var compactControls: some View {
        if isSearchExpanded {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.dsTravelNavy.opacity(0.78))

                TextField(
                    "",
                    text: $searchText,
                    prompt: Text("搜索收藏").foregroundStyle(Color.dsPaperInkSecondary)
                )
                .focused($isSearchFieldFocused)
                .submitLabel(.search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(Color.dsPaperInk)

                Button(action: collapseSearch) {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.dsTravelNavy)
                        .frame(width: 32, height: 32)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("取消搜索")
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .dsSceneGlass(
                radius: 24,
                tint: Color.dsBrandCream.opacity(0.08),
                interactive: true,
                legibility: .ambient
            )
            .transition(
                reduceMotion
                    ? .opacity
                    : .scale(scale: 0.86, anchor: .trailing).combined(with: .opacity)
            )
        } else {
            HStack(spacing: 9) {
                filterCapsule

                Button(action: expandSearch) {
                    Image(systemName: "magnifyingglass")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.dsTravelNavy)
                        .frame(width: 48, height: 48)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .dsSceneGlass(
                    radius: 24,
                    tint: Color.dsBrandCream.opacity(0.08),
                    interactive: true,
                    legibility: .ambient
                )
                .accessibilityLabel("搜索收藏")
            }
            .transition(
                reduceMotion
                    ? .opacity
                    : .scale(scale: 0.96, anchor: .leading).combined(with: .opacity)
            )
        }
    }

    private var filterCapsule: some View {
        HStack(spacing: 2) {
            ForEach(Filter.allCases) { option in
                Button {
                    filter = option
                } label: {
                    Text(option.rawValue)
                        .font(.footnote.weight(filter == option ? .bold : .medium))
                        .foregroundStyle(Color.dsPaperInk)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background {
                            if filter == option {
                                Capsule()
                                    .fill(Color.dsBrandCream.opacity(0.92))
                                    .overlay {
                                        Capsule().stroke(Color.white.opacity(0.78), lineWidth: 0.8)
                                    }
                                    .shadow(color: Color.dsTravelNavy.opacity(0.14), radius: 5, y: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(option.rawValue)筛选")
                .accessibilityAddTraits(filter == option ? .isSelected : [])
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity, minHeight: 48)
        .dsSceneGlass(
            radius: 24,
            tint: Color.dsBrandCream.opacity(0.06),
            interactive: true,
            legibility: .ambient
        )
    }

    private func expandSearch() {
        withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86)) {
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
        withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.88)) {
            isSearchExpanded = false
        }
    }

    private var emptyNotebook: some View {
        GeometryReader { proxy in
            VStack(spacing: 26) {
                VStack(spacing: 10) {
                    journalElement {
                        DSHologramBookmarkIcon(
                            size: 68,
                            tint: journalHologramTint,
                            glowColor: journalHologramGlow
                        )
                    }
                    .offset(x: journalIconOffsetX)

                    journalElement {
                        DSHologramText(
                            "还没有收藏",
                            size: 22,
                            weight: .heavy,
                            tint: journalHologramTint,
                            glowColor: journalHologramGlow,
                            alignment: .center
                        )
                    }
                    .offset(x: journalTitleOffsetX)

                    journalElement {
                        DSHologramText(
                            "在对话中收藏单词、语法或句子\n它们会整理在这里。",
                            size: 14,
                            weight: .medium,
                            tint: journalHologramTint,
                            glowColor: journalHologramGlow,
                            alignment: .center,
                            lineSpacing: 3
                        )
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    .offset(x: journalBodyOffsetX)
                }

                Button(action: onBrowseConversations) {
                    HStack(spacing: 6) {
                        Text("去对话看看")
                        Image(systemName: "chevron.right")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.dsTravelNavy)
                    .padding(.horizontal, 20)
                    .frame(minHeight: 42)
                    .overlay {
                        Capsule()
                            .stroke(Color.dsTravelNavy.opacity(0.88), lineWidth: 1.3)
                            .overlay {
                                Capsule()
                                    .stroke(
                                        Color.dsSkyDeep.opacity(0.36),
                                        style: StrokeStyle(lineWidth: 0.75, dash: [1.2, 2.4])
                                    )
                                    .offset(x: -0.45, y: 0.35)
                            }
                    }
                }
                .buttonStyle(.plain)
                .rotationEffect(.degrees(journalRotation))
                .offset(x: journalButtonOffsetX)
            }
            .frame(width: min(280, proxy.size.width * 0.72))
            .position(x: proxy.size.width * 0.545, y: proxy.size.height * 0.365)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResultsPanel: some View {
        GeometryReader { proxy in
            VStack(spacing: DSSpacing.sm) {
                journalElement {
                    Image(systemName: "text.magnifyingglass")
                        .font(.system(size: 35, weight: .medium))
                        .foregroundStyle(journalHologramTint)
                        .shadow(color: journalHologramGlow.opacity(0.52), radius: 3)
                }
                .offset(x: journalIconOffsetX)
                journalElement {
                    DSHologramText(
                        "没有找到相关收藏",
                        size: 19,
                        weight: .bold,
                        tint: journalHologramTint,
                        glowColor: journalHologramGlow,
                        alignment: .center
                    )
                }
                .offset(x: journalTitleOffsetX)
                journalElement {
                    DSHologramText(
                        "试试其他关键词或收藏类型",
                        size: 14,
                        weight: .medium,
                        tint: journalHologramTint,
                        glowColor: journalHologramGlow,
                        alignment: .center
                    )
                }
                .offset(x: journalBodyOffsetX)
            }
            .frame(width: min(280, proxy.size.width * 0.72))
            .position(x: proxy.size.width * 0.545, y: proxy.size.height * 0.35)
        }
    }

    private var journalRotation: Double { -9.25 }

    // Keep the action button as the visual anchor, then follow the notebook's
    // counter-clockwise page axis progressively farther left toward the top.
    private var journalIconOffsetX: CGFloat { -8 }
    private var journalTitleOffsetX: CGFloat { -13 }
    private var journalBodyOffsetX: CGFloat { -10 }
    private var journalButtonOffsetX: CGFloat { 8 }

    private var journalHologramTint: Color {
        Color(red: 0.16, green: 0.27, blue: 0.30)
    }

    private var journalHologramGlow: Color {
        Color(red: 0.48, green: 0.78, blue: 0.80)
    }

    private var journalSurfaceTransform: DSHologramTransform {
        DSHologramTransform(
            rotationZ: journalRotation,
            tiltX: 3.5,
            tiltY: -0.8,
            perspective: 0.16,
            scaleY: 0.99,
            footprintOffset: CGSize(width: -1.2, height: 10),
            extrusionOffset: CGSize(width: -0.2, height: 2.7)
        )
    }

    private func journalElement<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        DSHologramSurface(transform: journalSurfaceTransform) {
            content()
        }
    }

    private func favoritePanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        DSWorkbenchPaperSheet(radius: DSRadius.card, padding: DSSpacing.md) {
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
        .foregroundStyle(Color.dsPaperInk)
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
                            .foregroundStyle(Color.dsPaperInkSecondary)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    let groups = meaningGroups(for: favorite)
                    if groups.isEmpty {
                        Text("暂无中文释义")
                            .font(.subheadline)
                            .foregroundStyle(Color.dsPaperInkSecondary)
                    } else {
                        ForEach(groups) { group in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                partOfSpeechLabel(group)
                                Text(group.meaning)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.dsPaperInk)
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
                    .foregroundStyle(Color.dsPaperInkSecondary)
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
                    .foregroundStyle(Color.dsPaperInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let example = point?.examples.first {
                VStack(alignment: .leading, spacing: 3) {
                    Text(example.en)
                        .font(.footnote.weight(.medium))
                    Text(example.zh)
                        .font(.caption)
                        .foregroundStyle(Color.dsPaperInkSecondary)
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
                        .foregroundStyle(Color.dsPaperInkSecondary)
                }

                HStack(spacing: 5) {
                    Text(favorite.characterName)
                    Text("·")
                    favoriteDate(favorite.createdAt)
                }
                .font(.caption)
                .foregroundStyle(Color.dsPaperInkSecondary)
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
            .foregroundStyle(Color.dsPaperInkSecondary)
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

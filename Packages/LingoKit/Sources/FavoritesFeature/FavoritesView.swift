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
        speech: any SpeechService
    ) {
        self.favorites = favorites
        self.dictionary = dictionary
        self.grammarPoints = grammarPoints
        self.speech = speech
    }
}

/// 收藏夹：按单词、语法点和旧版句子分组展示。
public struct FavoritesView: View {
    private let deps: FavoritesDependencies
    @State private var favorites: [FavoriteDTO] = []
    @State private var wordEntries: [UUID: DictEntry] = [:]
    @State private var wordSelection: TokenSelection?
    @State private var isLoading = true

    public init(deps: FavoritesDependencies) {
        self.deps = deps
    }

    public var body: some View {
        Group {
            if favorites.isEmpty && !isLoading {
                ContentUnavailableView(
                    "收藏夹是空的",
                    systemImage: "star",
                    description: Text("可在单词释义窗或语法分析页点亮星标")
                )
            } else {
                List {
                    if !wordFavorites.isEmpty {
                        Section("单词") {
                            ForEach(wordFavorites) { favorite in
                                wordRow(favorite)
                            }
                            .onDelete { indexSet in
                                Task { await remove(at: indexSet, from: wordFavorites) }
                            }
                        }
                    }

                    if !grammarFavorites.isEmpty {
                        Section("语法点") {
                            ForEach(grammarFavorites) { favorite in
                                grammarRow(favorite)
                            }
                            .onDelete { indexSet in
                                Task { await remove(at: indexSet, from: grammarFavorites) }
                            }
                        }
                    }

                    if !sentenceFavorites.isEmpty {
                        Section("句子") {
                            ForEach(sentenceFavorites) { favorite in
                                sentenceRow(favorite)
                            }
                            .onDelete { indexSet in
                                Task { await remove(at: indexSet, from: sentenceFavorites) }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("收藏夹")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
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
            favoriteActions: wordFavoriteActions
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

    private var wordFavorites: [FavoriteDTO] {
        favorites.filter { $0.kind == .word }
    }

    private var grammarFavorites: [FavoriteDTO] {
        favorites.filter { $0.kind == .grammarPoint }
    }

    private var sentenceFavorites: [FavoriteDTO] {
        favorites.filter { $0.kind == .sentence }
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
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    let groups = meaningGroups(for: favorite)
                    if groups.isEmpty {
                        Text("暂无中文释义")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(groups) { group in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(group.partOfSpeech ?? "释义")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Color.dsSkyDeep)
                                    .frame(width: 66, alignment: .leading)
                                Text(group.meaning)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
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
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let example = point?.examples.first {
                VStack(alignment: .leading, spacing: 3) {
                    Text(example.en)
                        .font(.footnote.weight(.medium))
                    Text(example.zh)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 5) {
                    Text(favorite.characterName)
                    Text("·")
                    favoriteDate(favorite.createdAt)
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
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
            .foregroundStyle(.tertiary)
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

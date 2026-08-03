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

/// 收藏夹：以单词为新版收藏单位，同时兼容展示旧版句子收藏。
public struct FavoritesView: View {
    private let deps: FavoritesDependencies
    @State private var favorites: [FavoriteDTO] = []
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
                    description: Text("点击聊天或剧情中的单词，在释义弹窗右上角点亮星标")
                )
            } else {
                List {
                    ForEach(favorites) { favorite in
                        row(favorite)
                    }
                    .onDelete { indexSet in
                        Task { await remove(at: indexSet) }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.dsBackground)
            }
        }
        .navigationTitle("收藏夹")
        .background(Color.dsBackground)
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

    private func row(_ favorite: FavoriteDTO) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TappableText(
                tokens: TokenCache.tokens(for: favorite.sentence, cacheKey: "fav-\(favorite.id.uuidString)"),
                contextID: "fav-\(favorite.id.uuidString)",
                selection: wordSelection,
                onSelect: { wordSelection = $0 }
            )
            .font(favorite.kind == .word ? .title3.weight(.semibold) : .body)
            if let translation = favorite.translationZh {
                Text(translation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text(favorite.kind == .word ? "单词" : favorite.characterName)
                Spacer()
                Text(favorite.createdAt, style: .date)
                Button {
                    let speech = deps.speech
                    let sentence = favorite.sentence
                    Task { await speech.speak(sentence, language: "en-US") }
                } label: {
                    Image(systemName: "speaker.wave.2")
                        .foregroundStyle(Color.dsSky)
                }
                .buttonStyle(.borderless)
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
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
        favorites = (try? await deps.favorites.all()) ?? []
    }

    private func remove(at indexSet: IndexSet) async {
        for index in indexSet {
            guard favorites.indices.contains(index) else { continue }
            try? await deps.favorites.remove(id: favorites[index].id)
        }
        await reload()
    }
}

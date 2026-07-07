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

/// 收藏夹：翻阅收藏语句，句内单词可点查词，可播放朗读。
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
                    description: Text("长按聊天中的句子气泡，选择「收藏」")
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
            }
        }
        .navigationTitle("收藏夹")
        .wordLookupOverlay(
            selection: $wordSelection,
            dictionary: deps.dictionary,
            grammar: deps.grammarPoints,
            onSpeak: { word in
                let speech = deps.speech
                Task { await speech.speak(word, language: "en-US") }
            }
        )
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
            .font(.body)
            if let translation = favorite.translationZh {
                Text(translation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text(favorite.characterName)
                Spacer()
                Text(favorite.createdAt, style: .date)
                Button {
                    let speech = deps.speech
                    let sentence = favorite.sentence
                    Task { await speech.speak(sentence, language: "en-US") }
                } label: {
                    Image(systemName: "speaker.wave.2")
                }
                .buttonStyle(.borderless)
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
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

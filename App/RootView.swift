import ChatFeature
import FavoritesFeature
import HomeFeature
import SettingsFeature
import SwiftUI

struct RootView: View {
    let environment: AppEnvironment

    var body: some View {
        TabView {
            NavigationStack {
                HomeView()
            }
            .tabItem {
                Label("主页", systemImage: "house")
            }

            NavigationStack {
                ConversationListView(deps: chatDeps)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            NavigationLink {
                                FavoritesView(deps: favoritesDeps)
                            } label: {
                                Image(systemName: "star")
                            }
                            .accessibilityLabel("收藏夹")
                        }
                    }
            }
            .tabItem {
                Label("消息", systemImage: "bubble.left.and.bubble.right")
            }

            NavigationStack {
                SettingsView(settings: environment.llmSettings, router: environment.llmRouter)
            }
            .tabItem {
                Label("设置", systemImage: "gearshape")
            }
        }
    }

    private var chatDeps: ChatDependencies {
        ChatDependencies(
            chatStore: environment.chatStore,
            rosterStore: environment.rosterStore,
            favorites: environment.favoritesStore,
            llm: environment.llmRouter,
            dictionary: environment.dictionary,
            grammarPoints: environment.grammarPoints,
            speech: environment.speech,
            translator: environment.translator,
            audioSession: environment.audioSession
        )
    }

    private var favoritesDeps: FavoritesDependencies {
        FavoritesDependencies(
            favorites: environment.favoritesStore,
            dictionary: environment.dictionary,
            grammarPoints: environment.grammarPoints,
            speech: environment.speech
        )
    }
}

#Preview {
    RootView(environment: AppEnvironment())
}

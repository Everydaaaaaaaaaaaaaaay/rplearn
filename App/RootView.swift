import ChatFeature
import FavoritesFeature
import HomeFeature
import OnboardingFeature
import SettingsFeature
import SwiftUI

struct RootView: View {
    let environment: AppEnvironment

    private var showsOnboarding: Binding<Bool> {
        Binding(
            get: { environment.needsOnboarding == true },
            set: { newValue in
                if !newValue {
                    environment.needsOnboarding = false
                }
            }
        )
    }

    var body: some View {
        tabs
            .fullScreenCover(isPresented: showsOnboarding) {
                OnboardingFlowView(
                    deps: OnboardingDependencies(
                        rosterStore: environment.rosterStore,
                        scriptURL: Bundle.main.url(forResource: "onboarding_chat", withExtension: "json")!
                    )
                ) { character in
                    Task {
                        await environment.completeOnboarding(selected: character)
                    }
                }
                .interactiveDismissDisabled()
            }
    }

    private var tabs: some View {
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
            audioSession: environment.audioSession,
            memoryStore: environment.memoryStore,
            itemStore: environment.itemStore
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

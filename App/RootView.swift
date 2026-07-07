import ChatFeature
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
                ConversationListView()
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
}

#Preview {
    RootView(environment: AppEnvironment())
}

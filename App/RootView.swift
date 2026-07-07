import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack {
                Text("主页")
            }
            .tabItem {
                Label("主页", systemImage: "house")
            }

            NavigationStack {
                Text("消息")
            }
            .tabItem {
                Label("消息", systemImage: "bubble.left.and.bubble.right")
            }

            NavigationStack {
                Text("设置")
            }
            .tabItem {
                Label("设置", systemImage: "gearshape")
            }
        }
    }
}

#Preview {
    RootView()
}

import SwiftUI
import UIKit

enum Page: String, CaseIterable {
    case gallery, home, map, activities, stories, story, appointment, meetup, summary
    case messages, chat, contacts, person, me, learning, settings, memories
    var title: String {
        ["gallery":"界面实施基准", "home":"活动首页", "map":"世界地图", "activities":"城市活动", "stories":"剧情目录",
         "story":"剧情阅读", "appointment":"约定详情", "meetup":"赴约故事", "summary":"约定总结",
         "messages":"信息", "chat":"聊天", "contacts":"联系人", "person":"角色详情", "me":"我的",
         "learning":"学习", "settings":"设置", "memories":"共同记忆"][rawValue]!
    }
    var onPhoto: Bool { [.home,.map,.activities,.stories,.story,.appointment,.meetup,.summary,.messages,.contacts,.person].contains(self) }
    var tab: Int? {
        switch self { case .home,.activities,.stories: return 2; case .messages:return 0; case .contacts:return 1; case .me:return 3; default:return nil }
    }
}

final class Navigation: ObservableObject {
    @Published var page: Page
    init() { page = Page(rawValue: ProcessInfo.processInfo.environment["DESIGN_SCREEN"] ?? "gallery") ?? .gallery }
    func open(_ page: Page) {
        self.page = page
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first?.rootViewController?.setNeedsStatusBarAppearanceUpdate()
    }
}

final class Hosting: UIHostingController<DesignRoot> {
    let navigation: Navigation
    init(navigation: Navigation) { self.navigation = navigation; super.init(rootView: DesignRoot(navigation: navigation)) }
    @MainActor required dynamic init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not used") }
    override var preferredStatusBarStyle: UIStatusBarStyle { navigation.page.onPhoto ? .lightContent : (ProcessInfo.processInfo.environment["DESIGN_DARK"] == "1" ? .lightContent : .darkContent) }
}

@main final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Design", sessionRole: session.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let navigation = Navigation()
        let window = UIWindow(windowScene: windowScene)
        window.overrideUserInterfaceStyle = ProcessInfo.processInfo.environment["DESIGN_DARK"] == "1" ? .dark : .light
        window.rootViewController = Hosting(navigation: navigation)
        window.makeKeyAndVisible(); self.window = window
    }
}

struct DesignRoot: View {
    @ObservedObject var navigation: Navigation
    var body: some View {
        Screens(navigation: navigation)
            .fontDesign(.default).tint(UIStyle.tint)
            .background(UIStyle.canvas.ignoresSafeArea())
            .environment(\.dynamicTypeSize, ProcessInfo.processInfo.environment["DESIGN_LARGE"] == "1" ? .xxxLarge : .large)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let tab = navigation.page.tab { BottomTabs(selected: tab, navigate: navigation.open) }
            }
            .onAppear {
                guard let token = ProcessInfo.processInfo.environment["DESIGN_CAPTURE_TOKEN"] else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    let path = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("design-ready-\(token)")
                    try? navigation.page.rawValue.write(to: path, atomically: true, encoding: .utf8)
                }
            }
    }
}

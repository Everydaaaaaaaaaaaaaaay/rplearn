import SwiftUI
import UIKit

/// iOS 18–25 使用系统原生全宽 Tab Bar。这里只恢复系统背景，避免摄影页面
/// 透过完全透明的底栏影响可读性；不添加胶囊、圆角、阴影或按钮位置补偿。
struct LegacyTabBarAppearanceInstaller: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> InstallerViewController {
        let controller = InstallerViewController()
        controller.view.backgroundColor = .clear
        controller.view.isUserInteractionEnabled = false
        return controller
    }

    func updateUIViewController(_ controller: InstallerViewController, context: Context) {
        controller.installIfNeeded()
        Task { @MainActor [weak controller] in
            controller?.installIfNeeded()
        }
    }

    final class InstallerViewController: UIViewController {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            installIfNeeded()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            installIfNeeded()
        }

        func installIfNeeded() {
            guard let tabBar = resolvedTabBar() else { return }

            let appearance = UITabBarAppearance()
            if UIAccessibility.isReduceTransparencyEnabled {
                appearance.configureWithOpaqueBackground()
                appearance.backgroundColor = .systemBackground
                tabBar.isTranslucent = false
            } else {
                appearance.configureWithDefaultBackground()
                tabBar.isTranslucent = true
            }

            tabBar.standardAppearance = appearance
            tabBar.scrollEdgeAppearance = appearance
            tabBar.itemPositioning = .automatic
            tabBar.itemWidth = 0
            tabBar.itemSpacing = 0
        }

        /// SwiftUI 的 TabView 在系统版本间使用不同容器层级，因此先沿父链查找，
        /// 再从窗口根控制器递归定位原生 UITabBarController。
        private func resolvedTabBar() -> UITabBar? {
            if let tabBar = tabBarController?.tabBar {
                return tabBar
            }
            guard let root = viewIfLoaded?.window?.rootViewController else { return nil }
            return findTabBarController(from: root)?.tabBar
        }

        private func findTabBarController(from controller: UIViewController) -> UITabBarController? {
            if let tabController = controller as? UITabBarController {
                return tabController
            }
            if let presented = controller.presentedViewController,
               let match = findTabBarController(from: presented) {
                return match
            }
            for child in controller.children {
                if let match = findTabBarController(from: child) {
                    return match
                }
            }
            return nil
        }
    }
}

#Preview {
    RootView(environment: AppEnvironment())
}

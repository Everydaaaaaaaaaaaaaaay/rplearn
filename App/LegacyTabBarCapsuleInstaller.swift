import SwiftUI
import UIKit

struct LegacyTabBarCapsuleInstaller: UIViewControllerRepresentable {
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
        private static let capsuleTag = 0x4C_54_42
        private static let materialTag = 0x4C_54_4D
        private static let heightConstraintIdentifier = "LegacyTabBarCapsuleHeight"

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
            appearance.configureWithTransparentBackground()
            appearance.backgroundColor = .clear
            appearance.backgroundEffect = nil
            appearance.shadowColor = .clear
            tabBar.standardAppearance = appearance
            tabBar.scrollEdgeAppearance = appearance
            tabBar.isTranslucent = true
            tabBar.clipsToBounds = false

            if let existingCapsule = tabBar.viewWithTag(Self.capsuleTag) {
                updateCapsuleGeometry(existingCapsule, in: tabBar)
                tabBar.sendSubviewToBack(existingCapsule)
                return
            }

            let capsule = UIView()
            capsule.tag = Self.capsuleTag
            capsule.translatesAutoresizingMaskIntoConstraints = false
            capsule.isUserInteractionEnabled = false
            capsule.layer.cornerCurve = .continuous
            capsule.layer.shadowColor = UIColor.black.cgColor
            capsule.layer.shadowOpacity = 0.14
            capsule.layer.shadowRadius = 16
            capsule.layer.shadowOffset = CGSize(width: 0, height: 7)
            #if DEBUG
            if ProcessInfo.processInfo.environment["UI_TEST_FORCE_LEGACY_CHROME"] == "1" {
                capsule.isAccessibilityElement = true
                capsule.accessibilityIdentifier = "LegacyTabBarCapsule"
                capsule.accessibilityLabel = "旧系统底栏胶囊"
            }
            #endif

            let material = UIVisualEffectView(
                effect: UIAccessibility.isReduceTransparencyEnabled
                    ? nil
                    : UIBlurEffect(style: .systemUltraThinMaterialLight)
            )
            material.tag = Self.materialTag
            material.translatesAutoresizingMaskIntoConstraints = false
            material.isUserInteractionEnabled = false
            material.layer.cornerCurve = .continuous
            material.clipsToBounds = true
            let surfaceAlpha: CGFloat = UIAccessibility.isReduceTransparencyEnabled ? 0.96 : 0.50
            material.contentView.backgroundColor = UIColor(
                red: 0.985,
                green: 0.968,
                blue: 0.925,
                alpha: surfaceAlpha
            )
            material.layer.borderColor = UIColor.white.withAlphaComponent(0.72).cgColor
            material.layer.borderWidth = 0.8

            capsule.addSubview(material)
            tabBar.insertSubview(capsule, at: 0)

            let heightConstraint = capsule.heightAnchor.constraint(
                equalToConstant: Self.capsuleHeight(
                    tabBarHeight: tabBar.bounds.height,
                    safeAreaBottom: tabBar.safeAreaInsets.bottom
                )
            )
            heightConstraint.identifier = Self.heightConstraintIdentifier

            NSLayoutConstraint.activate([
                capsule.leadingAnchor.constraint(equalTo: tabBar.leadingAnchor, constant: 12),
                capsule.trailingAnchor.constraint(equalTo: tabBar.trailingAnchor, constant: -12),
                capsule.topAnchor.constraint(equalTo: tabBar.topAnchor, constant: 2),
                heightConstraint,
                material.leadingAnchor.constraint(equalTo: capsule.leadingAnchor),
                material.trailingAnchor.constraint(equalTo: capsule.trailingAnchor),
                material.topAnchor.constraint(equalTo: capsule.topAnchor),
                material.bottomAnchor.constraint(equalTo: capsule.bottomAnchor),
            ])

            updateCapsuleGeometry(capsule, in: tabBar)
            tabBar.sendSubviewToBack(capsule)
        }

        /// 胶囊覆盖 Tab 项内容并略微进入底部安全区，但不会包住 Home Indicator。
        /// 计算只依赖实际容器与安全区，因此适用于所有不支持 Liquid Glass 的版本。
        private func updateCapsuleGeometry(_ capsule: UIView, in tabBar: UITabBar) {
            let height = Self.capsuleHeight(
                tabBarHeight: tabBar.bounds.height,
                safeAreaBottom: tabBar.safeAreaInsets.bottom
            )
            capsule.constraints.first {
                $0.identifier == Self.heightConstraintIdentifier
            }?.constant = height
            capsule.layer.cornerRadius = height / 2
            capsule.viewWithTag(Self.materialTag)?.layer.cornerRadius = height / 2
        }

        static func capsuleHeight(tabBarHeight: CGFloat, safeAreaBottom: CGFloat) -> CGFloat {
            guard tabBarHeight > 0 else { return 60 }
            let itemAreaHeight = max(0, tabBarHeight - safeAreaBottom)
            let desiredHeight = itemAreaHeight + 11
            let availableHeight = max(0, tabBarHeight - 4)
            let minimumHeight = min(44, availableHeight)
            return min(64, max(minimumHeight, min(desiredHeight, availableHeight)))
        }

        /// SwiftUI 的 TabView 在不同系统版本中使用的容器层级不同。iOS 18
        /// 不保证这个探针控制器直接挂在 UITabBarController 下，因此先沿父链查找，
        /// 再从当前窗口根控制器递归定位，避免材质安装逻辑静默失效。
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

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
        private static let horizontalInset: CGFloat = 12
        private static let heightConstraintIdentifier = "LegacyTabBarCapsuleHeight"
        private static let topConstraintIdentifier = "LegacyTabBarCapsuleTop"
        private static let leadingConstraintIdentifier = "LegacyTabBarCapsuleLeading"
        private static let trailingConstraintIdentifier = "LegacyTabBarCapsuleTrailing"
        private var finalAlignmentTask: Task<Void, Never>?

        deinit {
            finalAlignmentTask?.cancel()
        }

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
            alignItemsWithCapsule(in: tabBar)
            scheduleFinalAlignment(in: tabBar)

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

            let geometry = Self.capsuleGeometry(
                tabBarHeight: tabBar.bounds.height,
                safeAreaBottom: tabBar.safeAreaInsets.bottom
            )
            let horizontalInsets = capsuleHorizontalInsets(in: tabBar)
            let heightConstraint = capsule.heightAnchor.constraint(equalToConstant: geometry.height)
            heightConstraint.identifier = Self.heightConstraintIdentifier
            let topConstraint = capsule.topAnchor.constraint(
                equalTo: tabBar.topAnchor,
                constant: geometry.top
            )
            topConstraint.identifier = Self.topConstraintIdentifier
            let leadingConstraint = capsule.leadingAnchor.constraint(
                equalTo: tabBar.leadingAnchor,
                constant: horizontalInsets.leading
            )
            leadingConstraint.identifier = Self.leadingConstraintIdentifier
            let trailingConstraint = capsule.trailingAnchor.constraint(
                equalTo: tabBar.trailingAnchor,
                constant: -horizontalInsets.trailing
            )
            trailingConstraint.identifier = Self.trailingConstraintIdentifier

            NSLayoutConstraint.activate([
                leadingConstraint,
                trailingConstraint,
                topConstraint,
                heightConstraint,
                material.leadingAnchor.constraint(equalTo: capsule.leadingAnchor),
                material.trailingAnchor.constraint(equalTo: capsule.trailingAnchor),
                material.topAnchor.constraint(equalTo: capsule.topAnchor),
                material.bottomAnchor.constraint(equalTo: capsule.bottomAnchor),
            ])

            updateCapsuleGeometry(capsule, in: tabBar)
            tabBar.sendSubviewToBack(capsule)
        }

        /// UIKit 在 iOS 18 上会把 Tab 按钮放在距 bar 顶部约 4pt、54pt 高的区域，
        /// 并不等同于简单的 `bar 高度 - safeArea`。以真实按钮 frame 居中，避免
        /// 用数学安全区推导后反而产生约 6pt 的纵向偏移。
        private func updateCapsuleGeometry(_ capsule: UIView, in tabBar: UITabBar) {
            let geometry = Self.capsuleGeometry(
                tabBarHeight: tabBar.bounds.height,
                safeAreaBottom: tabBar.safeAreaInsets.bottom
            )
            let top = tabItemCenterY(in: tabBar).map { $0 - geometry.height / 2 }
                ?? geometry.top
            capsule.constraints.first {
                $0.identifier == Self.heightConstraintIdentifier
            }?.constant = geometry.height
            tabBar.constraints.first {
                $0.identifier == Self.topConstraintIdentifier
            }?.constant = top
            let horizontalInsets = capsuleHorizontalInsets(in: tabBar)
            tabBar.constraints.first {
                $0.identifier == Self.leadingConstraintIdentifier
            }?.constant = horizontalInsets.leading
            tabBar.constraints.first {
                $0.identifier == Self.trailingConstraintIdentifier
            }?.constant = -horizontalInsets.trailing
            capsule.layer.cornerRadius = geometry.height / 2
            capsule.viewWithTag(Self.materialTag)?.layer.cornerRadius = geometry.height / 2
        }

        static func capsuleGeometry(
            tabBarHeight: CGFloat,
            safeAreaBottom: CGFloat
        ) -> (top: CGFloat, height: CGFloat) {
            guard tabBarHeight > 0 else { return (top: 2, height: 60) }
            let itemAreaHeight = max(0, tabBarHeight - safeAreaBottom)
            let desiredHeight = itemAreaHeight + 11
            let availableHeight = max(0, tabBarHeight - 4)
            let minimumHeight = min(44, availableHeight)
            let height = min(64, max(minimumHeight, min(desiredHeight, availableHeight)))
            return (top: 2, height: height)
        }

        /// iOS 18 的原生按钮布局和自定义胶囊使用不同的水平参考宽度。保持系统
        /// 管理按钮，并在最终布局后让胶囊边界跟随按钮组，避免系统再次覆盖修正。
        private func alignItemsWithCapsule(in tabBar: UITabBar) {
            tabBar.itemPositioning = .centered
            tabBar.itemWidth = 0
            tabBar.itemSpacing = 0
        }

        private func scheduleFinalAlignment(in tabBar: UITabBar) {
            guard finalAlignmentTask == nil else { return }
            finalAlignmentTask = Task { @MainActor [weak self, weak tabBar] in
                defer { self?.finalAlignmentTask = nil }
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled, let self, let tabBar else { return }
                self.alignItemsWithCapsule(in: tabBar)
                if let capsule = tabBar.viewWithTag(Self.capsuleTag) {
                    self.updateCapsuleGeometry(capsule, in: tabBar)
                }
            }
        }

        private func capsuleHorizontalInsets(
            in tabBar: UITabBar
        ) -> (leading: CGFloat, trailing: CGFloat) {
            let controls = tabItemControls(in: tabBar)
            let groups = groupedTabItemControls(controls, in: tabBar)
            guard groups.count == tabBar.items?.count,
                  groups.count > 1,
                  let first = groups.first?.first,
                  let last = groups.last?.first else {
                return (Self.horizontalInset, Self.horizontalInset)
            }
            let firstCenter = first.convert(first.bounds, to: tabBar).midX
            let lastCenter = last.convert(last.bounds, to: tabBar).midX
            let spacing = (lastCenter - firstCenter) / CGFloat(groups.count - 1)
            guard spacing > 0 else {
                return (Self.horizontalInset, Self.horizontalInset)
            }
            let leading = max(4, firstCenter - spacing / 2)
            let trailing = max(4, tabBar.bounds.width - lastCenter - spacing / 2)
            return (leading, trailing)
        }

        private func tabItemCenterY(in tabBar: UITabBar) -> CGFloat? {
            let controls = tabItemControls(in: tabBar)
            guard !controls.isEmpty else { return nil }
            return controls.map { $0.convert($0.bounds, to: tabBar).midY }
                .reduce(0, +) / CGFloat(controls.count)
        }

        private func tabItemControls(in tabBar: UITabBar) -> [UIControl] {
            var candidates: [UIControl] = []
            collectControls(in: tabBar, into: &candidates)
            candidates = candidates.filter { control in
                guard !control.isHidden, control.alpha > 0, control.bounds.height > 0 else {
                    return false
                }
                let frame = control.convert(control.bounds, to: tabBar)
                return frame.intersects(tabBar.bounds) && frame.width > 0
            }

            let itemLabels = Set(
                tabBar.items?.compactMap { item in
                    item.accessibilityLabel ?? item.title
                } ?? []
            )
            let labelMatches = candidates.filter { control in
                guard let label = control.accessibilityLabel else { return false }
                return itemLabels.contains(label)
            }
            let outerLabelMatches = outermostControls(in: labelMatches)
            let accessibleControls = outermostControls(
                in: candidates.filter(\.isAccessibilityElement)
            )
            let controls = outerLabelMatches.count == tabBar.items?.count
                ? outerLabelMatches
                : accessibleControls
            return controls.sorted {
                $0.convert($0.bounds, to: tabBar).midX
                    < $1.convert($1.bounds, to: tabBar).midX
            }
        }

        private func collectControls(in view: UIView, into controls: inout [UIControl]) {
            for subview in view.subviews {
                if let control = subview as? UIControl {
                    controls.append(control)
                }
                collectControls(in: subview, into: &controls)
            }
        }

        private func outermostControls(in controls: [UIControl]) -> [UIControl] {
            let identifiers = Set(controls.map(ObjectIdentifier.init))
            return controls.filter { control in
                var ancestor = control.superview
                while let view = ancestor {
                    if let parentControl = view as? UIControl,
                       identifiers.contains(ObjectIdentifier(parentControl)) {
                        return false
                    }
                    ancestor = view.superview
                }
                return true
            }
        }

        private func groupedTabItemControls(
            _ controls: [UIControl],
            in tabBar: UITabBar
        ) -> [[UIControl]] {
            var groups: [[UIControl]] = []
            for control in controls {
                let centerX = control.convert(control.bounds, to: tabBar).midX
                if let last = groups.last?.last {
                    let lastCenterX = last.convert(last.bounds, to: tabBar).midX
                    if abs(centerX - lastCenterX) < 1 {
                        groups[groups.count - 1].append(control)
                        continue
                    }
                }
                groups.append([control])
            }
            return groups
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

import SwiftUI
import UIKit

/// 导航推入、返回（含缩放转场和左缘滑动收尾）进行中时忽略新的触摸。
///
/// SwiftUI 的页面在转场动画里仍然可以点击：正在缩回的角色资料页会被点到原位置的“发消息”，
/// 转场中途发起的推入也可能被系统丢弃，使导航状态与界面不一致，之后再点同一入口没有反应。
/// 原生 UIKit 在转场期间同样不接受点击，这里在窗口最上层放一块平时完全透明、不参与命中测试的挡板，
/// 只在某个导航控制器正在转场时接住触摸。
struct NavigationTouchShieldInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> InstallerView {
        let view = InstallerView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: InstallerView, context: Context) {}

    final class InstallerView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window, !window.subviews.contains(where: { $0 is NavigationTouchShield }) else { return }
            let shield = NavigationTouchShield(frame: window.bounds)
            shield.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            window.addSubview(shield)
        }
    }
}

final class NavigationTouchShield: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isAccessibilityElement = false
        accessibilityElementsHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let root = window?.rootViewController, Self.hasNavigationTransition(in: root) else { return nil }
        return self
    }

    private static func hasNavigationTransition(in controller: UIViewController) -> Bool {
        if let navigation = controller as? UINavigationController, navigation.transitionCoordinator != nil {
            return true
        }
        return controller.children.contains(where: hasNavigationTransition)
    }
}

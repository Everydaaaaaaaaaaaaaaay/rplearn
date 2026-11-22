import SwiftUI
import UIKit

public extension View {
    /// 用缩放转场进入、自身显示系统导航栏、而来源页隐藏导航栏的子页面需要它。
    ///
    /// 缩放转场的交互返回（左缘拖、下拉）会把导航栏淡到透明；中途取消时 UIKit 不会淡回来，
    /// 顶栏连同返回按钮一起消失（栏还在，但看不见也点不到），页面只能靠手势离开。
    /// 页面重新出现或返回被取消时，把导航栏恢复为显示且不透明。
    /// 普通 push 转场不受影响，不需要加。
    func dsKeepsNavigationBarVisible(_ enabled: Bool = true) -> some View {
        background {
            if enabled {
                DSNavigationBarRecoveryBridge()
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
    }
}

private struct DSNavigationBarRecoveryBridge: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController {
        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            restoreIfTop()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            transitionCoordinator?.animate(alongsideTransition: nil) { [weak self] context in
                if context.isCancelled {
                    self?.restoreIfTop()
                    // 转场收尾可能在完成回调之后再改一次导航栏，下一轮再确认一遍。
                    DispatchQueue.main.async { [weak self] in self?.restoreIfTop() }
                }
            }
        }

        /// 只在本页仍是导航栈顶时恢复，避免影响真正返回后的来源页。
        private func restoreIfTop() {
            guard let navigationController else { return }
            var page: UIViewController = self
            while let parent = page.parent, parent !== navigationController { page = parent }
            guard navigationController.topViewController === page else { return }
            if navigationController.isNavigationBarHidden {
                navigationController.setNavigationBarHidden(false, animated: false)
            }
            // 缩放转场交互返回时把导航栏淡到透明，取消后不会淡回来：栏还在，但看不见也点不到。
            let bar = navigationController.navigationBar
            if bar.alpha < 1 {
                UIView.animate(withDuration: 0.15) { bar.alpha = 1 }
            }
        }
    }
}

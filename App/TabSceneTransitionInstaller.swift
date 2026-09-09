import DesignSystem
import SwiftUI
import UIKit

/// iOS 27 no longer supplies the short content dissolve when SwiftUI selects a tab.
/// Keep the native tab controller and SwiftUI's selection delegate; override only
/// its content animator, so navigation stacks and the glass tab bar stay intact.
struct TabSceneTransitionInstaller: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> InstallerViewController {
        let controller = InstallerViewController()
        controller.view.isUserInteractionEnabled = false
        controller.view.backgroundColor = .clear
        return controller
    }

    func updateUIViewController(_ controller: InstallerViewController, context: Context) {
        controller.installIfNeeded()
    }

    static func dismantleUIViewController(_ controller: InstallerViewController, coordinator: ()) {
        controller.uninstall()
    }

    final class InstallerViewController: UIViewController {
        private let proxy = TabSceneTransitionDelegate()
        private weak var installedController: UITabBarController?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            installIfNeeded()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            installIfNeeded()
        }

        func installIfNeeded() {
            guard let controller = tabBarController
                ?? viewIfLoaded?.window?.rootViewController.flatMap(findTabController)
            else { return }
            if installedController !== controller {
                uninstall()
                installedController = controller
            }
            guard controller.delegate !== proxy else { return }
            proxy.original = controller.delegate
            controller.delegate = proxy
        }

        func uninstall() {
            if let controller = installedController, controller.delegate === proxy {
                controller.delegate = proxy.original
            }
            installedController = nil
            proxy.original = nil
        }

        private func findTabController(_ controller: UIViewController) -> UITabBarController? {
            if let controller = controller as? UITabBarController { return controller }
            for child in controller.children {
                if let match = findTabController(child) { return match }
            }
            return nil
        }
    }
}

final class TabSceneTransitionDelegate: NSObject, UITabBarControllerDelegate {
    // NSObject capability queries are nonisolated; the installer only replaces
    // this weak forwarding reference on the main actor.
    nonisolated(unsafe) weak var original: (any UITabBarControllerDelegate)?

    // Forward selection, customization and future optional callbacks to SwiftUI.
    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || (original?.responds(to: selector) ?? false)
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        original?.responds(to: selector) == true ? original : super.forwardingTarget(for: selector)
    }

    func tabBarController(
        _ tabBarController: UITabBarController,
        animationControllerForTransitionFrom fromVC: UIViewController,
        to toVC: UIViewController
    ) -> (any UIViewControllerAnimatedTransitioning)? {
        TabSceneDissolveAnimator(reduceMotion: UIAccessibility.isReduceMotionEnabled)
    }
}

final class TabSceneDissolveAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    private let reduceMotion: Bool

    init(reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
    }

    func transitionDuration(using transitionContext: (any UIViewControllerContextTransitioning)?) -> TimeInterval {
        DSSceneTransition.duration(reduceMotion: reduceMotion)
    }

    func animateTransition(using context: any UIViewControllerContextTransitioning) {
        guard let destination = context.viewController(forKey: .to),
              let incoming = context.view(forKey: .to)
        else {
            context.completeTransition(false)
            return
        }
        let originalAlpha = incoming.alpha
        incoming.frame = context.finalFrame(for: destination)
        context.containerView.addSubview(incoming)
        incoming.alpha = 0
        // Keep the outgoing content opaque underneath to avoid a dark flash halfway
        // through the dissolve. UIKit owns removal and lifecycle on completion.
        UIView.animate(
            withDuration: transitionDuration(using: context),
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState,
                      reduceMotion ? .curveEaseOut : .curveEaseInOut]
        ) {
            incoming.alpha = originalAlpha
        } completion: { _ in
            let completed = !context.transitionWasCancelled
            if !completed { incoming.removeFromSuperview() }
            incoming.alpha = originalAlpha
            context.completeTransition(completed)
        }
    }
}

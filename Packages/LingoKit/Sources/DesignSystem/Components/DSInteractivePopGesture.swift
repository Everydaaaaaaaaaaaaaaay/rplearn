import SwiftUI
import UIKit

/// Controls UIKit's native interactive pop for the current pushed screen.
public struct DSInteractivePopGestureModifier: ViewModifier {
    let isEnabled: Bool
    let usesContentArea: Bool

    public func body(content: Content) -> some View {
        content.background {
            DSInteractivePopGestureBridge(isEnabled: isEnabled, usesContentArea: usesContentArea)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }
}

public extension View {
    func dsInteractivePopGesture(enabled: Bool = true) -> some View {
        modifier(DSInteractivePopGestureModifier(isEnabled: enabled, usesContentArea: false))
    }

    /// Controls the system's full-content pop gesture for the current screen.
    func dsInteractiveContentPopGesture(enabled: Bool) -> some View {
        modifier(DSInteractivePopGestureModifier(isEnabled: enabled, usesContentArea: true))
    }
}

private struct DSInteractivePopGestureBridge: UIViewControllerRepresentable {
    let isEnabled: Bool
    let usesContentArea: Bool

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.usesContentArea = usesContentArea
        return controller
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.allowsReturnGesture = isEnabled
        controller.updateGesture()
    }

    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) {
        controller.restoreGesture()
    }

    final class Controller: UIViewController, UIGestureRecognizerDelegate {
        var allowsReturnGesture = false
        var usesContentArea = false
        private weak var installedGesture: UIGestureRecognizer?
        private weak var previousDelegate: (any UIGestureRecognizerDelegate)?
        private var previousEnabled = false

        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            updateGesture()
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            restoreGesture()
        }

        func updateGesture() {
            if usesContentArea {
                updateContentGesture()
                return
            }
            guard allowsReturnGesture, viewIfLoaded?.window != nil,
                  let gesture = navigationController?.interactivePopGestureRecognizer
            else {
                restoreGesture()
                return
            }
            guard gesture.delegate !== self else { return }
            restoreGesture()
            installedGesture = gesture
            previousDelegate = gesture.delegate
            previousEnabled = gesture.isEnabled
            gesture.delegate = self
            gesture.isEnabled = true
        }

        private func updateContentGesture() {
            guard #available(iOS 26.0, *), viewIfLoaded?.window != nil,
                  let gesture = navigationController?.interactiveContentPopGestureRecognizer
            else {
                restoreGesture()
                return
            }
            if installedGesture !== gesture {
                restoreGesture()
                installedGesture = gesture
                previousDelegate = gesture.delegate
                previousEnabled = gesture.isEnabled
            }
            if gesture.delegate !== self { gesture.delegate = self }
            if gesture.isEnabled != allowsReturnGesture {
                gesture.isEnabled = allowsReturnGesture
            }
        }

        func restoreGesture() {
            if let gesture = installedGesture, gesture.delegate === self {
                gesture.delegate = previousDelegate
                gesture.isEnabled = previousEnabled
            }
            installedGesture = nil
            previousDelegate = nil
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard allowsReturnGesture, let navigationController else { return false }
            guard navigationController.viewControllers.count > 1,
                  navigationController.transitionCoordinator == nil else { return false }
            if usesContentArea, let pan = gestureRecognizer as? UIPanGestureRecognizer {
                let velocity = pan.velocity(in: navigationController.view)
                let isRTL = navigationController.view.effectiveUserInterfaceLayoutDirection == .rightToLeft
                return (isRTL ? -velocity.x : velocity.x) > abs(velocity.y) * 1.5
            }
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // Horizontal content can keep its own direction filter, while the
            // system's leading-edge recognizer remains a separate pop path.
            usesContentArea && otherGestureRecognizer !== navigationController?.interactivePopGestureRecognizer
        }
    }
}

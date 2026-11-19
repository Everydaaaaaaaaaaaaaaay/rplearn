import SwiftUI
import UIKit

/// Preserves UIKit's native interactive pop gesture when a pushed screen hides
/// the system navigation bar to draw its own custom top bar.
public struct DSInteractivePopGestureModifier: ViewModifier {
    let isEnabled: Bool

    public func body(content: Content) -> some View {
        content.background {
            DSInteractivePopGestureBridge(isEnabled: isEnabled)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }
}

public extension View {
    func dsInteractivePopGesture(enabled: Bool = true) -> some View {
        modifier(DSInteractivePopGestureModifier(isEnabled: enabled))
    }
}

private struct DSInteractivePopGestureBridge: UIViewControllerRepresentable {
    let isEnabled: Bool

    func makeUIViewController(context: Context) -> Controller {
        Controller()
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
            return navigationController.viewControllers.count > 1 && navigationController.transitionCoordinator == nil
        }
    }
}

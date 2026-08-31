import SwiftUI
import UIKit

struct LegacyTabBarCapsuleInstaller: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> InstallerViewController {
        InstallerViewController()
    }

    func updateUIViewController(_ controller: InstallerViewController, context: Context) {
        controller.installIfNeeded()
    }

    final class InstallerViewController: UIViewController {
        private static let capsuleTag = 0x4C_54_42

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            installIfNeeded()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            installIfNeeded()
        }

        func installIfNeeded() {
            guard let tabBar = tabBarController?.tabBar else { return }

            let appearance = UITabBarAppearance()
            appearance.configureWithTransparentBackground()
            appearance.backgroundColor = .clear
            appearance.backgroundEffect = nil
            appearance.shadowColor = .clear
            tabBar.standardAppearance = appearance
            tabBar.scrollEdgeAppearance = appearance
            tabBar.isTranslucent = true
            tabBar.clipsToBounds = false

            guard tabBar.viewWithTag(Self.capsuleTag) == nil else { return }

            let capsule = UIView()
            capsule.tag = Self.capsuleTag
            capsule.translatesAutoresizingMaskIntoConstraints = false
            capsule.isUserInteractionEnabled = false
            capsule.layer.cornerRadius = 32
            capsule.layer.cornerCurve = .continuous
            capsule.layer.shadowColor = UIColor.black.cgColor
            capsule.layer.shadowOpacity = 0.14
            capsule.layer.shadowRadius = 16
            capsule.layer.shadowOffset = CGSize(width: 0, height: 7)

            let material = UIVisualEffectView(
                effect: UIBlurEffect(style: .systemUltraThinMaterialLight)
            )
            material.translatesAutoresizingMaskIntoConstraints = false
            material.isUserInteractionEnabled = false
            material.layer.cornerRadius = 32
            material.layer.cornerCurve = .continuous
            material.clipsToBounds = true
            material.contentView.backgroundColor = UIColor(
                red: 0.985,
                green: 0.968,
                blue: 0.925,
                alpha: 0.50
            )
            material.layer.borderColor = UIColor.white.withAlphaComponent(0.72).cgColor
            material.layer.borderWidth = 0.8

            capsule.addSubview(material)
            tabBar.insertSubview(capsule, at: 0)

            NSLayoutConstraint.activate([
                capsule.leadingAnchor.constraint(equalTo: tabBar.leadingAnchor, constant: 12),
                capsule.trailingAnchor.constraint(equalTo: tabBar.trailingAnchor, constant: -12),
                capsule.topAnchor.constraint(equalTo: tabBar.topAnchor, constant: 4),
                capsule.bottomAnchor.constraint(equalTo: tabBar.bottomAnchor, constant: -4),
                material.leadingAnchor.constraint(equalTo: capsule.leadingAnchor),
                material.trailingAnchor.constraint(equalTo: capsule.trailingAnchor),
                material.topAnchor.constraint(equalTo: capsule.topAnchor),
                material.bottomAnchor.constraint(equalTo: capsule.bottomAnchor),
            ])
        }
    }
}

#Preview {
    RootView(environment: AppEnvironment())
}

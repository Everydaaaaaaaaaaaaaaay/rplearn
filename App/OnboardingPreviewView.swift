import SwiftUI

enum OnboardingPreviewMode: String, Identifiable {
    case placement, completeFlow
    var id: String { rawValue }
}

/// Reuses the production root and onboarding screens in a disposable account.
/// Authentication is already complete at this entry; no credentials are replayed.
struct OnboardingPreviewView: View {
    let mode: OnboardingPreviewMode
    @State private var environment: AppEnvironment?
    @State private var defaultsName = "onboarding-preview.\(UUID().uuidString)"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let environment {
                RootView(environment: environment, onExitOnboardingPreview: finish)
                    .defaultAppStorage(UserDefaults(suiteName: defaultsName)!)
            } else {
                ProgressView("正在准备测试")
            }
        }
        .task {
            guard environment == nil else { return }
            let preview = AppEnvironment(bootstrapAuthentication: false)
            preview.onboardingPreviewMode = mode
            environment = preview
        }
        .interactiveDismissDisabled()
    }

    private func finish() {
        UserDefaults.standard.removePersistentDomain(forName: defaultsName)
        dismiss()
    }
}

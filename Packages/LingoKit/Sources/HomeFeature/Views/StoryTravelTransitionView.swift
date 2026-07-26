import DesignSystem
import SwiftUI

struct StoryTravelPresentation: Identifiable {
    let id = UUID()
    let fromName: String
    let toName: String
    let storyTitle: String
}

struct StoryTravelTransitionView: View {
    let presentation: StoryTravelPresentation
    let onComplete: @MainActor () -> Void

    var body: some View {
        DSFlightTransitionView(
            fromName: presentation.fromName,
            toName: presentation.toName,
            statusText: "剧情专机 · 已解锁城市免费往返",
            statusIcon: "book.pages.fill",
            autoCompletionDelay: .milliseconds(900),
            onComplete: onComplete
        ) {
            VStack(spacing: DSSpacing.md) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(.white.opacity(0.16))
                        .frame(width: 92, height: 92)
                    Image(systemName: "airplane.arrival")
                        .font(.system(size: 42, weight: .bold))
                }

                VStack(spacing: DSSpacing.xs) {
                    Text("已抵达 \(presentation.toName)")
                        .font(.system(.largeTitle, design: .rounded, weight: .black))
                        .multilineTextAlignment(.center)

                    Text("即将开展《\(presentation.storyTitle)》")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.82))
                }
                .padding(.horizontal, DSSpacing.lg)

                Label("位置已同步", systemImage: "checkmark.seal.fill")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))

                Spacer()
            }
            .foregroundStyle(.white)
        }
        .interactiveDismissDisabled()
    }
}

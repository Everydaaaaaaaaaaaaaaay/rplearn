import SwiftUI

public struct CalloutCard<Content: View, Trailing: View>: View {
    public enum Kind: Sendable {
        case coach
        case speech
        case quiz

        var title: String {
            switch self {
            case .coach: "改进建议"
            case .speech: "口语点评"
            case .quiz: "小测验"
            }
        }

        var icon: String {
            switch self {
            case .coach: "sparkles"
            case .speech: "waveform.badge.mic"
            case .quiz: "checkmark.bubble.fill"
            }
        }

        var tint: Color {
            switch self {
            case .coach: .dsCoach
            case .speech: .dsSpeech
            case .quiz: .dsQuiz
            }
        }
    }

    private let kind: Kind
    private let maxWidth: CGFloat?
    private let trailing: Trailing
    private let content: Content

    public init(
        kind: Kind,
        maxWidth: CGFloat? = 320,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) {
        self.kind = kind
        self.maxWidth = maxWidth
        self.trailing = trailing()
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.xs) {
                Label(kind.title, systemImage: kind.icon)
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(kind.tint)
                Spacer(minLength: DSSpacing.xs)
                trailing
            }
            content
        }
        .padding(DSSpacing.sm)
        .frame(maxWidth: maxWidth, alignment: .leading)
        .background(kind.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: DSRadius.inline, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DSRadius.inline, style: .continuous)
                .stroke(kind.tint.opacity(0.16), lineWidth: 1)
        }
    }
}

public extension CalloutCard where Trailing == EmptyView {
    init(
        kind: Kind,
        maxWidth: CGFloat? = 320,
        @ViewBuilder content: () -> Content
    ) {
        self.init(kind: kind, maxWidth: maxWidth, trailing: { EmptyView() }, content: content)
    }
}

import SwiftUI

public struct CalloutCard<Content: View, Trailing: View>: View {
    public enum Kind: Sendable {
        case coach
        case speech
        case quiz

        var title: String {
            switch self {
            case .coach: "咕咕建议"
            case .speech: "咕咕口语点评"
            case .quiz: "咕咕小测验"
            }
        }

        var icon: String {
            switch self {
            case .coach: "bird.fill"
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
    private let coachPersona: DSCoachPersona
    private let maxWidth: CGFloat?
    private let trailing: Trailing
    private let content: Content

    public init(
        kind: Kind,
        coachPersona: DSCoachPersona = .gugu,
        maxWidth: CGFloat? = 320,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) {
        self.kind = kind
        self.coachPersona = coachPersona
        self.maxWidth = maxWidth
        self.trailing = trailing()
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.xs) {
                calloutHeading
                Spacer(minLength: DSSpacing.xs)
                trailing
            }
            content
        }
        .padding(DSSpacing.sm)
        .frame(maxWidth: maxWidth, alignment: .leading)
        .background(
            Color.dsSurface,
            in: RoundedRectangle(cornerRadius: DSRadius.inline, style: .continuous)
        )
        .overlay(alignment: .leading) {
            Capsule()
                .fill(kind.tint)
                .frame(width: 3, height: 36)
                .padding(.leading, 1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: DSRadius.inline, style: .continuous)
                .stroke(kind.tint.opacity(0.22), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.035), radius: 6, y: 2)
    }

    @ViewBuilder
    private var calloutHeading: some View {
        switch kind {
        case .coach:
            HStack(spacing: 6) {
                BrandMascotView(pose: coachPersona.pose, size: 26, showsShadow: false)
                Text(coachPersona.title)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(coachPersona.title)
            .font(.system(.caption, design: .rounded, weight: .bold))
            .foregroundStyle(kind.tint)
        case .speech, .quiz:
            Label(kind.title, systemImage: kind.icon)
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(kind.tint)
        }
    }
}

public extension CalloutCard where Trailing == EmptyView {
    init(
        kind: Kind,
        coachPersona: DSCoachPersona = .gugu,
        maxWidth: CGFloat? = 320,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            kind: kind,
            coachPersona: coachPersona,
            maxWidth: maxWidth,
            trailing: { EmptyView() },
            content: content
        )
    }
}

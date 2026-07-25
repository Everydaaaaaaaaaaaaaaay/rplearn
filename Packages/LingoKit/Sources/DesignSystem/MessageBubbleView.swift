import SwiftUI
import UIKit

/// 聊天气泡（纯 UI）。内容由外部提供，供聊天页与剧情聊天皮肤复用。
public struct MessageBubble<Content: View>: View {
    public enum Side {
        case incoming
        case outgoing
    }

    private let side: Side
    private let content: Content

    public init(side: Side, @ViewBuilder content: () -> Content) {
        self.side = side
        self.content = content()
    }

    public var body: some View {
        HStack {
            if side == .outgoing {
                Spacer(minLength: 48)
            }
            content
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.bubble, style: .continuous))
            if side == .incoming {
                Spacer(minLength: 48)
            }
        }
    }

    @ViewBuilder
    private var background: some View {
        switch side {
        case .incoming:
            Color.dsBubbleIncoming
        case .outgoing:
            Color.dsSky
        }
    }
}

/// 「正在输入」三点动画。
public struct TypingIndicator: View {
    public init() {}

    public var body: some View {
        PhaseAnimator([0, 1, 2]) { phase in
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(.secondary)
                        .frame(width: 7, height: 7)
                        .opacity(phase == index ? 1 : 0.35)
                }
            }
        } animation: { _ in
            .easeInOut(duration: 0.3)
        }
        .accessibilityLabel("对方正在输入")
    }
}

#Preview {
    VStack(spacing: 12) {
        MessageBubble(side: .incoming) {
            Text("hey! how's it going")
        }
        MessageBubble(side: .outgoing) {
            Text("Pretty good! Just finished my homework.")
                .foregroundStyle(.white)
        }
        MessageBubble(side: .incoming) {
            TypingIndicator()
        }
    }
    .padding()
}

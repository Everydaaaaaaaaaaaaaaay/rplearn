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
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            if side == .incoming {
                Spacer(minLength: 48)
            }
        }
    }

    @ViewBuilder
    private var background: some View {
        switch side {
        case .incoming:
            Color(.systemGray5)
        case .outgoing:
            Color.accentColor
        }
    }
}

/// 「正在输入」三点动画。
public struct TypingIndicator: View {
    @State private var phase = 0

    public init() {}

    public var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(.secondary)
                    .frame(width: 7, height: 7)
                    .opacity(phase == index ? 1 : 0.35)
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                withAnimation(.easeInOut(duration: 0.25)) {
                    phase = (phase + 1) % 3
                }
            }
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

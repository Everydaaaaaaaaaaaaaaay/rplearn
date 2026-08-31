import SwiftUI
import UIKit

public enum MessageBubbleGroupPosition: Sendable, Equatable {
    case single
    case first
    case middle
    case last
}

/// 聊天气泡（纯 UI）。内容由外部提供，供聊天页与剧情聊天皮肤复用。
public struct MessageBubble<Content: View>: View {
    public enum Side {
        case incoming
        case outgoing
    }

    private let side: Side
    private let groupPosition: MessageBubbleGroupPosition
    private let leadingAccessory: AnyView?
    private let content: Content

    public init(
        side: Side,
        groupPosition: MessageBubbleGroupPosition = .single,
        @ViewBuilder content: () -> Content
    ) {
        self.side = side
        self.groupPosition = groupPosition
        self.leadingAccessory = nil
        self.content = content()
    }

    /// 为发出气泡提供一个紧贴气泡左侧、垂直居中的附件槽位。
    ///
    /// 附件使用类型擦除，避免让所有现有调用方承担第二个泛型参数。
    public init<Accessory: View>(
        side: Side,
        groupPosition: MessageBubbleGroupPosition = .single,
        @ViewBuilder leadingAccessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) {
        self.side = side
        self.groupPosition = groupPosition
        self.leadingAccessory = AnyView(leadingAccessory())
        self.content = content()
    }

    public var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if side == .incoming, let leadingAccessory {
                leadingAccessory
                    .padding(.trailing, 6)
            }
            if side == .outgoing {
                Spacer(minLength: leadingAccessory == nil ? 48 : 4)
                if let leadingAccessory {
                    leadingAccessory
                }
            }
            content
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(background)
                .clipShape(bubbleShape)
                .overlay {
                    // iOS 26 原生渲染下气泡边缘已经清楚，维持已验收效果；
                    // iOS 18 只为浅色收到气泡补一条克制的可读性边界。
                    if DSPlatformVisualPolicy.requiresIOS18RenderingCompensation,
                       case .incoming = side {
                        bubbleShape.stroke(Color.dsBrandInk.opacity(0.18), lineWidth: 0.9)
                    }
                }
            if side == .incoming {
                Spacer(minLength: 48)
            }
        }
    }

    private var bubbleShape: UnevenRoundedRectangle {
        let full = DSRadius.bubble
        let joined: CGFloat = 7

        return switch (side, groupPosition) {
        case (_, .single):
            UnevenRoundedRectangle(
                topLeadingRadius: full,
                bottomLeadingRadius: full,
                bottomTrailingRadius: full,
                topTrailingRadius: full,
                style: .continuous
            )
        case (.incoming, .first):
            UnevenRoundedRectangle(
                topLeadingRadius: full,
                bottomLeadingRadius: joined,
                bottomTrailingRadius: full,
                topTrailingRadius: full,
                style: .continuous
            )
        case (.incoming, .middle):
            UnevenRoundedRectangle(
                topLeadingRadius: joined,
                bottomLeadingRadius: joined,
                bottomTrailingRadius: full,
                topTrailingRadius: full,
                style: .continuous
            )
        case (.incoming, .last):
            UnevenRoundedRectangle(
                topLeadingRadius: joined,
                bottomLeadingRadius: full,
                bottomTrailingRadius: full,
                topTrailingRadius: full,
                style: .continuous
            )
        case (.outgoing, .first):
            UnevenRoundedRectangle(
                topLeadingRadius: full,
                bottomLeadingRadius: full,
                bottomTrailingRadius: joined,
                topTrailingRadius: full,
                style: .continuous
            )
        case (.outgoing, .middle):
            UnevenRoundedRectangle(
                topLeadingRadius: full,
                bottomLeadingRadius: full,
                bottomTrailingRadius: joined,
                topTrailingRadius: joined,
                style: .continuous
            )
        case (.outgoing, .last):
            UnevenRoundedRectangle(
                topLeadingRadius: full,
                bottomLeadingRadius: full,
                bottomTrailingRadius: full,
                topTrailingRadius: joined,
                style: .continuous
            )
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var body: some View {
        Group {
            if reduceMotion {
                dots(activeIndex: nil)
            } else {
                PhaseAnimator([0, 1, 2]) { phase in
                    dots(activeIndex: phase)
                } animation: { _ in
                    .easeInOut(duration: 0.3)
                }
            }
        }
        .accessibilityLabel("对方正在输入")
    }

    private func dots(activeIndex: Int?) -> some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(.secondary)
                    .frame(width: 7, height: 7)
                    .opacity(activeIndex == nil || activeIndex == index ? 1 : 0.35)
            }
        }
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

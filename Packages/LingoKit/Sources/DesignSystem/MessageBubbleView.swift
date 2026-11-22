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

    @Environment(\.tutorialBubbleFocused) private var tutorialFocused
    private let side: Side
    private let groupPosition: MessageBubbleGroupPosition
    private let leadingAccessory: AnyView?
    private let contextMenuContent: AnyView?
    private var onMenuRequest: ((CGRect) -> Void)?
    @State private var surfaceAnchor = BubbleSurfaceAnchor.Reference()
    private let content: Content

    public init(
        side: Side,
        groupPosition: MessageBubbleGroupPosition = .single,
        @ViewBuilder content: () -> Content
    ) {
        self.side = side
        self.groupPosition = groupPosition
        self.leadingAccessory = nil
        self.contextMenuContent = nil
        self.content = content()
    }

    /// 将上下文菜单直接锚定到气泡表面，而不是包含头像和对齐留白的整行。
    public init<Menu: View>(
        side: Side,
        groupPosition: MessageBubbleGroupPosition = .single,
        onMenuRequest: ((CGRect) -> Void)? = nil,
        @ViewBuilder contextMenu: () -> Menu,
        @ViewBuilder content: () -> Content
    ) {
        self.side = side
        self.groupPosition = groupPosition
        self.leadingAccessory = nil
        self.contextMenuContent = AnyView(contextMenu())
        self.onMenuRequest = onMenuRequest
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
        self.contextMenuContent = nil
        self.content = content()
    }

    /// 带头像或纠错入口时，菜单仍只作用于真正的消息气泡。
    public init<Accessory: View, Menu: View>(
        side: Side,
        groupPosition: MessageBubbleGroupPosition = .single,
        @ViewBuilder leadingAccessory: () -> Accessory,
        onMenuRequest: ((CGRect) -> Void)? = nil,
        @ViewBuilder contextMenu: () -> Menu,
        @ViewBuilder content: () -> Content
    ) {
        self.side = side
        self.groupPosition = groupPosition
        self.leadingAccessory = AnyView(leadingAccessory())
        self.contextMenuContent = AnyView(contextMenu())
        self.onMenuRequest = onMenuRequest
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
            interactiveBubble
            if side == .incoming {
                Spacer(minLength: 48)
            }
        }
    }

    @ViewBuilder
    private var interactiveBubble: some View {
        if let onMenuRequest {
            bubbleSurface
                .background { BubbleSurfaceAnchor(reference: surfaceAnchor) }
                .highPriorityGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                    if let frame = surfaceAnchor.frame { onMenuRequest(frame) }
                })
                .accessibilityAction(named: "消息操作") {
                    if let frame = surfaceAnchor.frame { onMenuRequest(frame) }
                }
        } else if let contextMenuContent {
            bubbleSurface
                .contextMenu { contextMenuContent }
        } else {
            bubbleSurface
        }
    }

    private var bubbleSurface: some View {
        content
            .font(.puff(.body, Puff.Weight.body))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(background)
            .clipShape(bubbleShape)
            .overlay {
                if case .incoming = side {
                    bubbleShape.strokeBorder(Puff.Palette.line, lineWidth: 1.2)
                }
            }
            // 蓬蓬厚卡片的唇边：气泡像一颗可以按下去的软糖。
            .background {
                bubbleShape
                    .fill(lip)
                    .offset(y: Self.lipHeight)
            }
            .padding(.bottom, Self.lipHeight)
            .tutorialFocus("chat.bubble", active: tutorialFocused, shape: bubbleShape)
            .contentShape(.interaction, bubbleShape)
            .contentShape(.contextMenuPreview, bubbleShape)
    }

    private static var lipHeight: CGFloat { 2.5 }

    private var lip: Color {
        switch side {
        case .incoming: Puff.Palette.lip
        case .outgoing: PuffCandy.sky.lip
        }
    }

    private var bubbleShape: UnevenRoundedRectangle {
        let full: CGFloat = 20
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
            Puff.Palette.card
        case .outgoing:
            PuffCandy.sky.base
        }
    }

}

/// Read the live bubble position only when its menu opens. Scrolling and keyboard
/// animation never write geometry back into SwiftUI state.
private struct BubbleSurfaceAnchor: UIViewRepresentable {
    @MainActor final class Reference {
        weak var view: UIView?
        var frame: CGRect? { view.map { $0.convert($0.bounds, to: nil) } }
    }

    let reference: Reference

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        reference.view = view
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        reference.view = view
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
                    .fill([PuffCandy.sky, .bubblegum, .sunny][index].base)
                    .frame(width: 8, height: 8)
                    .offset(y: activeIndex == index ? -3 : 0)
                    .opacity(activeIndex == nil || activeIndex == index ? 1 : 0.55)
            }
        }
        .padding(.vertical, 3)
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

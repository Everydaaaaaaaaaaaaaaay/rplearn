import DesignSystem
import PersistenceKit
import SwiftUI

extension ChatView {
    func presentBubbleMenu(_ message: MessageDTO, frame: CGRect) {
        // Keep the actual bubble and current responder in place. A system context
        // preview dismisses the keyboard and snapshots the old bubble coordinates.
        Haptics.selection()
        bubbleMenuFrame = frame
        bubbleMenuMessage = message
    }

    @ViewBuilder
    var bubbleActionsOverlay: some View {
        if let message = bubbleMenuMessage {
            GeometryReader { viewport in
                let origin = viewport.frame(in: .global).origin
                let bubble = bubbleMenuFrame.offsetBy(dx: -origin.x, dy: -origin.y)
                let width = min(224, max(0, viewport.size.width - 24))
                let height = min(bubbleMenuSize.height, max(0, viewport.size.height - 16))
                let below = bubble.maxY + 8
                let top = below + height <= viewport.size.height - 8
                    ? below : max(8, bubble.minY - height - 8)
                let leading = message.role == .user ? bubble.maxX - width : bubble.minX
                ZStack(alignment: .topLeading) {
                    Color.black.opacity(0.12)
                        .contentShape(Rectangle())
                        .onTapGesture { bubbleMenuMessage = nil }
                        .accessibilityLabel("关闭消息菜单")
                        .accessibilityAddTraits(.isButton)
                    ScrollView {
                        VStack(spacing: 0) { bubbleMenu(message) }
                            .buttonStyle(ChatMessageMenuButtonStyle())
                            .padding(.vertical, 4)
                            .onGeometryChange(for: CGSize.self) { $0.size } action: { bubbleMenuSize = $0 }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(width: width, height: height)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                    .overlay { RoundedRectangle(cornerRadius: 20).stroke(Color.dsBorder, lineWidth: 0.5) }
                    .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
                    .offset(x: min(max(12, leading), max(12, viewport.size.width - width - 12)),
                            y: min(top, max(8, viewport.size.height - height - 8)))
                    .accessibilityIdentifier("chat.bubbleMenu")
                    .accessibilityAction(.escape) { bubbleMenuMessage = nil }
                }
            }
            .transition(.opacity)
        }
    }
}

private struct ChatMessageMenuButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .labelStyle(.titleAndIcon)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
            .background(configuration.isPressed ? Color.primary.opacity(0.08) : .clear)
    }
}

import SwiftUI

/// 两页保留在同一视图树；横拖只改变位置，不重建聊天和草稿。
struct ChatLearningPager<Chat: View, Learning: View>: View {
    @Binding var learningSelected: Bool
    let enabled: Bool
    @ViewBuilder let chat: () -> Chat
    @ViewBuilder let learning: () -> Learning
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState(resetTransaction: Transaction(animation: .interactiveSpring(duration: 0.28, extraBounce: 0))) private var translation: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                chat().frame(width: geometry.size.width).accessibilityHidden(learningSelected)
                    .allowsHitTesting(!learningSelected)
                learning().frame(width: geometry.size.width).accessibilityHidden(!learningSelected)
                    .allowsHitTesting(learningSelected)
            }
            .frame(width: geometry.size.width * 2, alignment: .leading)
            .offset(x: (learningSelected ? -geometry.size.width : 0) + translation)
            .frame(width: geometry.size.width, alignment: .leading)
            .clipped()
            .transaction { if reduceMotion { $0.animation = nil } }
            .animation(reduceMotion ? .easeOut(duration: 0.15) : .interactiveSpring(duration: 0.28, extraBounce: 0), value: learningSelected)
            .simultaneousGesture(
                DragGesture(minimumDistance: 18)
                    .updating($translation) { value, state, _ in
                        guard accepts(value, size: geometry.size) else { return }
                        let direction = learningSelected ? max(0, value.translation.width) : min(0, value.translation.width)
                        state = min(geometry.size.width, max(-geometry.size.width, direction))
                    }
                    .onEnded { value in
                        guard accepts(value, size: geometry.size) else { return }
                        let distance = value.translation.width
                        let predicted = value.predictedEndTranslation.width
                        let threshold = geometry.size.width * 0.25
                        if !learningSelected && (distance < -threshold || predicted < -threshold * 1.5) { learningSelected = true }
                        else if learningSelected && (distance > threshold || predicted > threshold * 1.5) { learningSelected = false }
                    }, including: enabled ? .all : .none
            )
        }
    }
    private func accepts(_ value: DragGesture.Value, size: CGSize) -> Bool {
        enabled && value.startLocation.x > 28 && value.startLocation.y < size.height - 90 &&
        abs(value.translation.width) > abs(value.translation.height) * 1.5
    }
}

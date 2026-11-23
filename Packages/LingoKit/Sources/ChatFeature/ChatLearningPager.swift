import SwiftUI
import DesignSystem

/// 两页保留在同一视图树；横拖只改变位置，不重建聊天和草稿。
struct ChatLearningPager<Chat: View, Learning: View>: View {
    @Binding var learningSelected: Bool
    let translation: GestureState<CGFloat>
    let enabled: Bool
    @ViewBuilder let chat: () -> Chat
    @ViewBuilder let learning: () -> Learning
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let pageOffset = (learningSelected ? -geometry.size.width : 0) + translation.wrappedValue
            HStack(spacing: 0) {
                chat().frame(width: geometry.size.width).accessibilityHidden(learningSelected)
                    .allowsHitTesting(!learningSelected)
                learning().frame(width: geometry.size.width).accessibilityHidden(!learningSelected)
                    .allowsHitTesting(learningSelected)
            }
            .frame(width: geometry.size.width * 2, alignment: .leading)
            .offset(x: pageOffset)
            .frame(width: geometry.size.width, alignment: .leading)
            .clipped()
            .transaction { if reduceMotion { $0.animation = nil } }
            .animation(reduceMotion ? .easeOut(duration: 0.15) : .interactiveSpring(duration: 0.28, extraBounce: 0), value: learningSelected)
            .simultaneousGesture(
                DragGesture(minimumDistance: 18)
                    .updating(translation) { value, state, _ in
                        guard accepts(value, size: geometry.size) else { return }
                        let raw = value.translation.width
                        let isOverscrolling = (learningSelected && raw < 0) || (!learningSelected && raw > 0)
                        if isOverscrolling {
                            state = min(36, max(-36, raw * 0.16))
                        } else {
                            state = min(geometry.size.width, max(-geometry.size.width, raw))
                        }
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
        guard enabled, value.startLocation.x > 28, value.startLocation.y < size.height - 90,
              abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return false }
        if #available(iOS 26.0, *), !learningSelected, value.translation.width > 0 {
            return false
        }
        return true
    }
}

/// Gesture progress is consumed by the moving pages and backdrop, outside the chat host.
struct ChatLearningBackdrop: View {
    let regionID: String?
    let learningSelected: Bool
    let translation: GestureState<CGFloat>
    /// 这位旅伴的糖果色（与头像外圈、学习页一致）。
    let candy: PuffCandy

    var body: some View {
        // 聊天页与学习页共用一张“聊天壁纸”：旅伴色的天空带 + 很淡的旅行涂鸦，左右滑动时背景不变。
        PuffPageBackdrop()
            .environment(\.puffPageTint, candy)
    }
}

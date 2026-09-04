import DesignSystem
import SwiftUI

/// 点词查词浮窗：挂在聊天根视图上。
/// 被点词经 anchorPreference 上报 bounds，在词上/下方渲染 DictCardView（空间不足自动翻转），
/// 渐入动画，点遮罩关闭。
public struct WordLookupOverlayModifier: ViewModifier {
    @Binding var selection: TokenSelection?
    let dictionary: DictDatabase
    let grammar: GrammarPointStore
    let onSpeak: (@MainActor (String) -> Void)?
    let favoriteActions: WordFavoriteActions?
    let aiFallback: (@Sendable (String) async -> String?)?
    let exampleTranslationActions: DictExampleTranslationActions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public func body(content: Content) -> some View {
        content
            .overlayPreferenceValue(SelectedTokenAnchorKey.self) { anchor in
                if let selection, let anchor {
                    GeometryReader { proxy in
                        let wordRect = proxy[anchor]
                        let cardHeight = DictCardLayout.maximumHeight
                        let halfWidth = DictCardLayout.width / 2
                        let halfHeight = cardHeight / 2
                        let showBelow = wordRect.maxY + cardHeight + 12 < proxy.size.height
                        ZStack {
                            // 遮罩：点击关闭
                            Color.black.opacity(0.001)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    self.selection = nil
                                }
                                .accessibilityHidden(true)
                            DictCardView(
                                target: .word(selection.word),
                                phraseCandidates: selection.phraseCandidates,
                                contextText: selection.contextText,
                                dictionary: dictionary,
                                grammar: grammar,
                                onSpeak: onSpeak,
                                favoriteActions: favoriteActions,
                                aiFallback: aiFallback,
                                exampleTranslationActions: exampleTranslationActions,
                                onDismiss: { self.selection = nil }
                            )
                            .id(selection)
                            .position(
                                x: min(
                                    max(halfWidth + 10, wordRect.midX),
                                    proxy.size.width - halfWidth - 10
                                ),
                                y: showBelow
                                    ? wordRect.maxY + 8 + halfHeight
                                    : max(halfHeight + 8, wordRect.minY - 8 - halfHeight)
                            )
                        }
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .scale(scale: 0.96, anchor: showBelow ? .top : .bottom)
                                    .combined(with: .opacity)
                        )
                    }
                }
            }
            .animation(reduceMotion ? .easeOut(duration: 0.15) : DSAnimation.snappy, value: selection)
    }
}

extension View {
    /// 为视图挂载点词查词浮窗。
    public func wordLookupOverlay(
        selection: Binding<TokenSelection?>,
        dictionary: DictDatabase,
        grammar: GrammarPointStore,
        onSpeak: (@MainActor (String) -> Void)? = nil,
        favoriteActions: WordFavoriteActions? = nil,
        aiFallback: (@Sendable (String) async -> String?)? = nil,
        exampleTranslationActions: DictExampleTranslationActions
    ) -> some View {
        modifier(
            WordLookupOverlayModifier(
                selection: selection,
                dictionary: dictionary,
                grammar: grammar,
                onSpeak: onSpeak,
                favoriteActions: favoriteActions,
                aiFallback: aiFallback,
                exampleTranslationActions: exampleTranslationActions
            )
        )
    }
}

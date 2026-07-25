import DesignSystem
import SwiftUI

/// 点词查词浮窗：挂在聊天根视图上。
/// 被点词经 anchorPreference 上报 bounds，在词上/下方渲染 DictCardView（空间不足自动翻转），
/// 渐入动画，点遮罩关闭（plan.md §3.1）。
public struct WordLookupOverlayModifier: ViewModifier {
    @Binding var selection: TokenSelection?
    let dictionary: DictDatabase
    let grammar: GrammarPointStore
    let onSpeak: (@MainActor (String) -> Void)?
    let aiFallback: (@Sendable (String) async -> String?)?

    public func body(content: Content) -> some View {
        content
            .overlayPreferenceValue(SelectedTokenAnchorKey.self) { anchor in
                if let selection, let anchor {
                    GeometryReader { proxy in
                        let wordRect = proxy[anchor]
                        let cardHeight: CGFloat = 380
                        let showBelow = wordRect.maxY + cardHeight + 12 < proxy.size.height
                        ZStack {
                            // 遮罩：点击关闭
                            Color.black.opacity(0.001)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    self.selection = nil
                                }
                            DictCardView(
                                target: .word(selection.word),
                                dictionary: dictionary,
                                grammar: grammar,
                                onSpeak: onSpeak,
                                aiFallback: aiFallback
                            )
                            .id(selection)
                            .position(
                                x: min(max(170, wordRect.midX), proxy.size.width - 170),
                                y: showBelow ? wordRect.maxY + 8 + 190 : max(198, wordRect.minY - 8 - 190)
                            )
                        }
                        .transition(.scale(scale: 0.94, anchor: .center).combined(with: .opacity))
                    }
                    .ignoresSafeArea(.keyboard)
                }
            }
            .animation(DSAnimation.bouncy, value: selection)
    }
}

extension View {
    /// 为视图挂载点词查词浮窗。
    public func wordLookupOverlay(
        selection: Binding<TokenSelection?>,
        dictionary: DictDatabase,
        grammar: GrammarPointStore,
        onSpeak: (@MainActor (String) -> Void)? = nil,
        aiFallback: (@Sendable (String) async -> String?)? = nil
    ) -> some View {
        modifier(
            WordLookupOverlayModifier(
                selection: selection,
                dictionary: dictionary,
                grammar: grammar,
                onSpeak: onSpeak,
                aiFallback: aiFallback
            )
        )
    }
}

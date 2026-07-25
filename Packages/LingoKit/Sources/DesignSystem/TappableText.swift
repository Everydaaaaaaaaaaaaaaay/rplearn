import CoreKit
import SwiftUI

/// 一次点词选择：contextID 区分不同消息/上下文，tokenID 定位到具体 token。
public struct TokenSelection: Hashable, Sendable {
    public let contextID: String
    public let tokenID: Int
    public let word: String

    public init(contextID: String, tokenID: Int, word: String) {
        self.contextID = contextID
        self.tokenID = tokenID
        self.word = word
    }
}

/// 被选中 token 的锚点（浮窗定位用）。同一时刻至多一个 token 上报非 nil。
public struct SelectedTokenAnchorKey: PreferenceKey {
    public static var defaultValue: Anchor<CGRect>? { nil }

    public static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

/// 逐词可点文本：FlowLayout + 每 token 一个 Text。
/// 流式输出期间请用普通 Text，finished 后再换本组件（plan.md §3.1）。
public struct TappableText: View {
    private let tokens: [TextToken]
    private let contextID: String
    private let keywords: Set<String>
    private let textColor: Color?
    private let selection: TokenSelection?
    private let onSelect: (TokenSelection) -> Void

    public init(
        tokens: [TextToken],
        contextID: String,
        keywords: Set<String> = [],
        textColor: Color? = nil,
        selection: TokenSelection? = nil,
        onSelect: @escaping (TokenSelection) -> Void
    ) {
        self.tokens = tokens
        self.contextID = contextID
        self.keywords = keywords
        self.textColor = textColor
        self.selection = selection
        self.onSelect = onSelect
    }

    public var body: some View {
        FlowLayout {
            ForEach(tokens) { token in
                tokenView(token)
            }
        }
    }

    @ViewBuilder
    private func tokenView(_ token: TextToken) -> some View {
        let isSelected = selection?.contextID == contextID && selection?.tokenID == token.id
        let isKeyword = token.word.map { keywords.contains($0) } ?? false

        if let word = token.word {
            Button {
                onSelect(TokenSelection(contextID: contextID, tokenID: token.id, word: word))
            } label: {
                Text(token.display)
                    .underline(isKeyword, pattern: .dot)
                    .foregroundStyle(textColor ?? .primary)
                    .background(
                        isSelected ? Color.yellow.opacity(0.35) : .clear,
                        in: RoundedRectangle(cornerRadius: 4)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("查看释义")
                .anchorPreference(key: SelectedTokenAnchorKey.self, value: .bounds) { anchor in
                    isSelected ? anchor : nil
                }
        } else {
            Text(token.display)
                .foregroundStyle(textColor ?? .primary)
        }
    }
}

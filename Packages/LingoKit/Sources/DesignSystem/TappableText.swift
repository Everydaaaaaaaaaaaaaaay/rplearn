import CoreKit
import SwiftUI

/// 一次点词选择：contextID 区分不同消息/上下文，tokenID 定位到具体 token。
public struct TokenSelection: Hashable, Sendable {
    public let contextID: String
    public let tokenID: Int
    public let word: String
    public let grammarPointID: String?

    public init(
        contextID: String,
        tokenID: Int,
        word: String,
        grammarPointID: String? = nil
    ) {
        self.contextID = contextID
        self.tokenID = tokenID
        self.word = word
        self.grammarPointID = grammarPointID
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
/// 流式输出期间请用普通 Text，finished 后再换本组件。
public struct TappableText: View {
    private let tokens: [TextToken]
    private let contextID: String
    private let keywords: Set<String>
    private let grammarPointIDs: [Int: String]
    private let textColor: Color?
    private let selection: TokenSelection?
    private let onSelect: (TokenSelection) -> Void

    public init(
        tokens: [TextToken],
        contextID: String,
        keywords: Set<String> = [],
        grammarPointIDs: [Int: String] = [:],
        textColor: Color? = nil,
        selection: TokenSelection? = nil,
        onSelect: @escaping (TokenSelection) -> Void
    ) {
        self.tokens = tokens
        self.contextID = contextID
        self.keywords = keywords
        self.grammarPointIDs = grammarPointIDs
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
            if let grammarPointID = grammarPointIDs[token.id] {
                Menu {
                    Button {
                        onSelect(
                            TokenSelection(
                                contextID: contextID,
                                tokenID: token.id,
                                word: word
                            )
                        )
                    } label: {
                        Label("单词释义", systemImage: "character.book.closed")
                    }
                    Button {
                        onSelect(
                            TokenSelection(
                                contextID: contextID,
                                tokenID: token.id,
                                word: word,
                                grammarPointID: grammarPointID
                            )
                        )
                    } label: {
                        Label("语法释义", systemImage: "text.book.closed")
                    }
                } label: {
                    tokenLabel(
                        token,
                        isKeyword: false,
                        isGrammar: true,
                        isSelected: isSelected
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(token.display)
                .accessibilityHint("选择查看单词释义或语法释义")
                .anchorPreference(key: SelectedTokenAnchorKey.self, value: .bounds) { anchor in
                    isSelected ? anchor : nil
                }
            } else {
                Button {
                    onSelect(TokenSelection(contextID: contextID, tokenID: token.id, word: word))
                } label: {
                    tokenLabel(
                        token,
                        isKeyword: isKeyword,
                        isGrammar: false,
                        isSelected: isSelected
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint("查看单词释义")
                .anchorPreference(key: SelectedTokenAnchorKey.self, value: .bounds) { anchor in
                    isSelected ? anchor : nil
                }
            }
        } else {
            Text(token.display)
                .foregroundStyle(textColor ?? .primary)
        }
    }

    private func tokenLabel(
        _ token: TextToken,
        isKeyword: Bool,
        isGrammar: Bool,
        isSelected: Bool
    ) -> some View {
        Text(token.display)
            .underline(isKeyword, pattern: .dot)
            .foregroundStyle(isGrammar ? Color.dsSkyDeep : (textColor ?? .primary))
            .background(
                isSelected
                    ? (isGrammar ? Color.dsSky.opacity(0.18) : Color.yellow.opacity(0.35))
                    : .clear,
                in: RoundedRectangle(cornerRadius: 4)
            )
            .contentShape(Rectangle())
    }
}

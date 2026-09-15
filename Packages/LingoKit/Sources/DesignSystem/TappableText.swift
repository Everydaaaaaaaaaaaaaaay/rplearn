import CoreKit
import SwiftUI

/// 一次点词选择：contextID 区分不同消息/上下文，tokenID 定位到具体 token。
public struct TokenSelection: Hashable, Sendable {
    public let contextID: String
    public let tokenID: Int
    public let word: String
    public let phraseCandidates: [String]

    public init(
        contextID: String,
        tokenID: Int,
        word: String,
        phraseCandidates: [String] = []
    ) {
        self.contextID = contextID
        self.tokenID = tokenID
        self.word = word
        self.phraseCandidates = phraseCandidates
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
    private let textColor: Color?
    private let selection: TokenSelection?
    private let lookupOnLongPress: Bool
    private let onSelect: (TokenSelection) -> Void

    public init(
        tokens: [TextToken],
        contextID: String,
        keywords: Set<String> = [],
        textColor: Color? = nil,
        selection: TokenSelection? = nil,
        lookupOnLongPress: Bool = false,
        onSelect: @escaping (TokenSelection) -> Void
    ) {
        self.tokens = tokens
        self.contextID = contextID
        self.keywords = keywords
        self.textColor = textColor
        self.selection = selection
        self.lookupOnLongPress = lookupOnLongPress
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

        if token.word != nil, lookupOnLongPress {
            tokenLabel(token, isKeyword: isKeyword, isSelected: isSelected)
                .onLongPressGesture { onSelect(makeSelection(for: token)) }
                .accessibilityHint("长按查看单词释义")
                .accessibilityAction(named: "查看单词释义") { onSelect(makeSelection(for: token)) }
                .anchorPreference(key: SelectedTokenAnchorKey.self, value: .bounds) { anchor in
                    isSelected ? anchor : nil
                }
        } else if token.word != nil {
            Button {
                onSelect(makeSelection(for: token))
            } label: {
                tokenLabel(
                    token,
                    isKeyword: isKeyword,
                    isSelected: isSelected
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint("查看单词释义")
            .anchorPreference(key: SelectedTokenAnchorKey.self, value: .bounds) { anchor in
                isSelected ? anchor : nil
            }
        } else {
            Text(token.display)
                .foregroundStyle(textColor ?? .primary)
        }
    }

    private func makeSelection(for token: TextToken) -> TokenSelection {
        TokenSelection(
            contextID: contextID,
            tokenID: token.id,
            word: token.word ?? token.display,
            phraseCandidates: phraseCandidates(around: token.id)
        )
    }

    /// 生成包含被点词的 2–4 词窗口，长短语优先交给本地词典精确匹配。
    private func phraseCandidates(around tokenID: Int) -> [String] {
        let words = tokens.compactMap { token -> (id: Int, word: String)? in
            token.word.map { (token.id, $0) }
        }
        guard let selectedIndex = words.firstIndex(where: { $0.id == tokenID }) else {
            return []
        }
        var results: [String] = []
        var seen = Set<String>()
        for length in stride(from: min(4, words.count), through: 2, by: -1) {
            let firstStart = max(0, selectedIndex - length + 1)
            let lastStart = min(selectedIndex, words.count - length)
            guard firstStart <= lastStart else { continue }
            let midpointOffset = length / 2
            let candidateStarts = Array(firstStart...lastStart)
            let starts = candidateStarts.sorted { lhs, rhs in
                let lhsDistance = abs(lhs + midpointOffset - selectedIndex)
                let rhsDistance = abs(rhs + midpointOffset - selectedIndex)
                return lhsDistance < rhsDistance
            }
            for start in starts {
                let phrase = words[start..<(start + length)]
                    .map(\.word)
                    .joined(separator: " ")
                if seen.insert(phrase).inserted {
                    results.append(phrase)
                }
            }
        }
        return results
    }

    private func tokenLabel(
        _ token: TextToken,
        isKeyword: Bool,
        isSelected: Bool
    ) -> some View {
        Text(token.display)
            .underline(isKeyword, pattern: .dot)
            .foregroundStyle(textColor ?? .primary)
            .background(
                isSelected
                    ? Color.yellow.opacity(0.35)
                    : .clear,
                in: RoundedRectangle(cornerRadius: 4)
            )
            .contentShape(Rectangle())
    }
}

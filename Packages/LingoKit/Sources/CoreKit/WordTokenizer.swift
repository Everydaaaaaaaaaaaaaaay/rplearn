import Foundation
import NaturalLanguage

/// 可点词渲染的最小单元：一个单词 + 其尾随标点/空白合并为一个 token。
/// `display` 用于展示（如 "Hello, "），`word` 为可点的小写词形；nil 表示不可点（纯标点/emoji/数字）。
public struct TextToken: Sendable, Equatable, Identifiable {
    public let id: Int
    public var display: String
    public var word: String?

    public init(id: Int, display: String, word: String?) {
        self.id = id
        self.display = display
        self.word = word
    }
}

/// NLTokenizer 词界分词（纯函数，可单测）。
public enum WordTokenizer {
    public static func tokenize(_ text: String) -> [TextToken] {
        guard !text.isEmpty else { return [] }
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text

        var ranges: [Range<String.Index>] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            ranges.append(range)
            return true
        }

        var tokens: [TextToken] = []
        var cursor = text.startIndex

        func appendGap(_ gap: Substring) {
            guard !gap.isEmpty else { return }
            if tokens.isEmpty {
                tokens.append(TextToken(id: 0, display: String(gap), word: nil))
            } else {
                tokens[tokens.count - 1].display += gap
            }
        }

        for range in ranges {
            if cursor < range.lowerBound {
                appendGap(text[cursor..<range.lowerBound])
            }
            let raw = String(text[range])
            let isWord = raw.contains(where: \.isLetter)
            tokens.append(TextToken(id: tokens.count, display: raw, word: isWord ? raw.lowercased() : nil))
            cursor = range.upperBound
        }
        if cursor < text.endIndex {
            appendGap(text[cursor..<text.endIndex])
        }
        // 重新编号（首 token 可能由 gap 生成）
        return tokens.enumerated().map { index, token in
            TextToken(id: index, display: token.display, word: token.word)
        }
    }
}

/// Cache by context and verify source text: messages and asynchronously enriched
/// dictionary rows can change while retaining the same presentation identity.
@MainActor
public enum TokenCache {
    private final class Box {
        let sourceText: String
        let tokens: [TextToken]
        init(sourceText: String, tokens: [TextToken]) {
            self.sourceText = sourceText
            self.tokens = tokens
        }
    }

    private static let cache = NSCache<NSString, AnyObject>()

    public static func tokens(for text: String, cacheKey: String) -> [TextToken] {
        if let box = cache.object(forKey: cacheKey as NSString) as? Box, box.sourceText == text {
            return box.tokens
        }
        let tokens = WordTokenizer.tokenize(text)
        cache.setObject(Box(sourceText: text, tokens: tokens), forKey: cacheKey as NSString)
        return tokens
    }
}

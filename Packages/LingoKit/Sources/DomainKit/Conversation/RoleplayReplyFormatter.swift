import Foundation

/// 将模型的一次角色回复整理为一组符合即时通讯习惯的短消息。
///
/// 提示词负责让模型主动分条；这里仍保留确定性兜底，避免模型偶尔输出空段落
/// 或把很多句子塞进同一个气泡。
public enum RoleplayReplyFormatter {
    public static let maximumSentencesPerMessage = 2
    public static let maximumWordsPerMessage = 16
    public static let maximumMessagesPerReply = 3
    private static let maximumWordsForTwoSentenceMessage = 12

    public static func messages(from rawText: String) -> [String] {
        let lines = rawText
            .components(separatedBy: .newlines)
            .map(normalizeInlineWhitespace)
            .filter { !$0.isEmpty }

        let chunks = lines.flatMap(messageChunks)
        guard chunks.count > maximumMessagesPerReply else { return chunks }

        // 即使模型偶尔超量，也只保留真人一次连续发送通常会出现的前三条。
        // 前两条负责承接语境；若后文有问题，优先保留它，避免裁掉对话接续点。
        let head = Array(chunks.prefix(maximumMessagesPerReply - 1))
        let remaining = chunks.dropFirst(maximumMessagesPerReply - 1)
        let tail = remaining.first(where: looksLikeQuestion) ?? remaining.first
        return tail.map { head + [$0] } ?? head
    }

    /// 流式阶段仍使用一个临时气泡，但折叠模型输出的空行，并隐藏测验标记。
    public static func streamingPreview(from rawText: String) -> String {
        let replyText = rawText.components(separatedBy: "<quiz>").first ?? rawText
        return normalizeInlineWhitespace(replyText)
    }

    private static func messageChunks(from line: String) -> [String] {
        var sentences: [String] = []
        line.enumerateSubstrings(
            in: line.startIndex..<line.endIndex,
            options: .bySentences
        ) { substring, _, _, _ in
            guard let substring else { return }
            let sentence = normalizeInlineWhitespace(substring)
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
        }

        guard !sentences.isEmpty else { return [line] }

        let shortParts = sentences.flatMap(splitLongSentence)
        var messages: [String] = []
        var current: [String] = []

        for part in shortParts {
            let candidate = (current + [part]).joined(separator: " ")
            let canAppend = current.count < maximumSentencesPerMessage
                && wordCount(candidate) <= maximumWordsPerMessage
                && (current.isEmpty || wordCount(candidate) <= maximumWordsForTwoSentenceMessage)
            if canAppend {
                current.append(part)
            } else {
                if !current.isEmpty {
                    messages.append(current.joined(separator: " "))
                }
                current = [part]
            }
        }
        if !current.isEmpty {
            messages.append(current.joined(separator: " "))
        }
        return messages
    }

    private static func splitLongSentence(_ sentence: String) -> [String] {
        var remaining = sentence.split(whereSeparator: \.isWhitespace).map(String.init)
        var chunks: [String] = []

        while remaining.count > maximumWordsPerMessage {
            let lowerBound = min(5, maximumWordsPerMessage)
            let pauseBoundary = stride(
                from: maximumWordsPerMessage - 1,
                through: lowerBound - 1,
                by: -1
            ).first { index in
                isNaturalPause(remaining[index])
            }
            let connectorBoundary = stride(
                from: maximumWordsPerMessage - 1,
                through: lowerBound,
                by: -1
            ).first { index in
                ["and", "but", "so", "because", "while"].contains(remaining[index].lowercased())
            }
            let defaultEnd = remaining.count - maximumWordsPerMessage < 5
                ? Int(ceil(Double(remaining.count) / 2))
                : maximumWordsPerMessage
            let end = pauseBoundary.map { $0 + 1 } ?? connectorBoundary ?? defaultEnd
            chunks.append(remaining[..<end].joined(separator: " "))
            remaining.removeFirst(end)
        }
        if !remaining.isEmpty {
            chunks.append(remaining.joined(separator: " "))
        }
        return chunks
    }

    private static func isNaturalPause(_ word: String) -> Bool {
        if let last = word.last, ",;:—–".contains(last) { return true }
        return word.unicodeScalars.contains { $0.properties.isEmojiPresentation }
    }

    private static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    private static func looksLikeQuestion(_ text: String) -> Bool {
        if text.contains("?") { return true }
        guard let firstToken = text
            .split(whereSeparator: \.isWhitespace)
            .first
        else { return false }
        let firstWord = firstToken
            .lowercased()
            .trimmingCharacters(in: .punctuationCharacters)
        return [
            "what", "why", "how", "when", "where", "who", "which",
            "do", "does", "did", "are", "is", "can", "could", "would",
            "will", "have", "has", "you", "fancy", "reckon", "wanna",
        ].contains(firstWord)
    }

    private static func normalizeInlineWhitespace(_ text: String) -> String {
        text
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .joined(separator: " ")
    }
}

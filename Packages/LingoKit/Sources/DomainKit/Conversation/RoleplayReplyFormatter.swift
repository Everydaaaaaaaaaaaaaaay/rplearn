import Foundation

/// 将模型的一次角色回复整理为一组符合即时通讯习惯的短消息。
///
/// 提示词负责让模型主动分条；这里仍保留确定性兜底，避免模型偶尔输出空段落
/// 或把很多句子塞进同一个气泡。
public enum RoleplayReplyFormatter {
    public static let maximumSentencesPerMessage = 2
    public static let preferredWordsPerMessage = 9
    public static let maximumWordsPerMessage = 12
    public static let maximumMessagesPerReply = 4
    private static let maximumWordsForTwoSentenceMessage = 9
    private static let minimumWordsAroundOptionalPause = 3

    public static func messages(from rawText: String) -> [String] {
        let lines = rawText
            .components(separatedBy: .newlines)
            .map(normalizeInlineWhitespace)
            .filter { !$0.isEmpty }

        let chunks = lines.flatMap(messageChunks)
        guard chunks.count > maximumMessagesPerReply else { return chunks }

        // 即使模型偶尔超量，也只保留真人一次连续发送较自然的四条。
        // 前三条负责承接语境；若后文有问题，优先保留它，避免裁掉对话接续点。
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

        var messages: [String] = []
        var current: [String] = []

        for sentence in sentences {
            let parts = splitLongSentence(sentence)

            // 同一句话被语气停顿拆开后，边界必须保留为发送动作，不能又拼回一个气泡。
            if parts.count > 1 {
                var remainingParts = parts
                if !current.isEmpty {
                    let candidate = (current + [remainingParts[0]]).joined(separator: " ")
                    if wordCount(candidate) <= preferredWordsPerMessage {
                        messages.append(candidate)
                        remainingParts.removeFirst()
                    } else {
                        messages.append(current.joined(separator: " "))
                    }
                    current = []
                }
                messages.append(contentsOf: remainingParts)
                continue
            }

            guard let part = parts.first else { continue }
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
            let end = naturalBoundary(in: remaining, maximumEnd: maximumWordsPerMessage)
                ?? balancedBoundary(for: remaining.count)
            chunks.append(remaining[..<end].joined(separator: " "))
            remaining.removeFirst(end)
        }

        // 不超过硬上限的从句也可在自然停顿处续发，模拟口语换气，而非机械等待句号。
        if remaining.count > preferredWordsPerMessage,
           let end = naturalBoundary(in: remaining, maximumEnd: remaining.count - 1) {
            chunks.append(remaining[..<end].joined(separator: " "))
            remaining.removeFirst(end)
        }
        if !remaining.isEmpty {
            chunks.append(remaining.joined(separator: " "))
        }
        return chunks
    }

    private static func naturalBoundary(
        in words: [String],
        maximumEnd: Int
    ) -> Int? {
        let latestEnd = min(maximumEnd, words.count - minimumWordsAroundOptionalPause)
        let earliestEnd = minimumWordsAroundOptionalPause
        guard latestEnd >= earliestEnd else { return nil }

        // 标点留在上一条；连接词留在下一条，读起来更像同一口头表达的延续。
        for end in stride(from: latestEnd, through: earliestEnd, by: -1) {
            if isNaturalPause(words[end - 1]) {
                return end
            }
        }
        for end in stride(from: latestEnd, through: earliestEnd, by: -1) {
            let connector = words[end]
                .lowercased()
                .trimmingCharacters(in: .punctuationCharacters)
            if ["and", "but", "so", "because", "while", "though", "then"].contains(connector) {
                return end
            }
        }
        return nil
    }

    private static func balancedBoundary(for wordCount: Int) -> Int {
        if wordCount <= maximumWordsPerMessage * 2 {
            return Int(ceil(Double(wordCount) / 2))
        }
        return maximumWordsPerMessage
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

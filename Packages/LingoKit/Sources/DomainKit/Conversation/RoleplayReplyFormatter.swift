import Foundation

/// 将模型的一次角色回复整理为一组符合即时通讯习惯的短消息。
///
/// 提示词负责让模型主动分条；这里仍保留确定性兜底，避免模型偶尔输出空段落
/// 或把很多句子塞进同一个气泡。
public enum RoleplayReplyFormatter {
    public static let maximumMessageCount = 3
    public static let maximumSentencesPerMessage = 2

    public static func messages(from rawText: String) -> [String] {
        let lines = rawText
            .components(separatedBy: .newlines)
            .map(normalizeInlineWhitespace)
            .filter { !$0.isEmpty }

        var messages = lines.flatMap(sentenceChunks)
        guard messages.count > maximumMessageCount else { return messages }

        let overflow = messages
            .dropFirst(maximumMessageCount - 1)
            .joined(separator: " ")
        messages = Array(messages.prefix(maximumMessageCount - 1))
        messages.append(overflow)
        return messages
    }

    /// 流式阶段仍使用一个临时气泡，但折叠模型输出的空行，并隐藏测验标记。
    public static func streamingPreview(from rawText: String) -> String {
        let replyText = rawText.components(separatedBy: "<quiz>").first ?? rawText
        return normalizeInlineWhitespace(replyText)
    }

    private static func sentenceChunks(from line: String) -> [String] {
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
        return stride(from: 0, to: sentences.count, by: maximumSentencesPerMessage)
            .map { start in
                let end = min(start + maximumSentencesPerMessage, sentences.count)
                return sentences[start..<end].joined(separator: " ")
            }
    }

    private static func normalizeInlineWhitespace(_ text: String) -> String {
        text
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .joined(separator: " ")
    }
}

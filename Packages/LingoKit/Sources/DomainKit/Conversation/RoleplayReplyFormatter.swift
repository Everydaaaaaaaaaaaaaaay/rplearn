import Foundation

/// 将模型的一次角色回复整理为一组符合即时通讯习惯的短消息。
///
/// 提示词负责让模型主动分条；这里仍保留确定性兜底，避免模型偶尔输出空段落
/// 或把很多句子塞进同一个气泡。
public enum RoleplayReplyFormatter {
    public static let maximumSentencesPerMessage = 2

    public static func messages(from rawText: String) -> [String] {
        let lines = rawText
            .components(separatedBy: .newlines)
            .map(normalizeInlineWhitespace)
            .filter { !$0.isEmpty }

        // 不在这里强行把超出的消息重新并回最后一个气泡。模型偶尔多写几句时，
        // 多几个短气泡仍比一个重新膨胀的长段落更像真实聊天，也不会再次引入空行。
        return lines.flatMap(sentenceChunks)
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

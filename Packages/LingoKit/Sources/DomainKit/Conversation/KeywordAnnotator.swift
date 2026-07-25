import CoreKit
import DictKit
import Foundation

/// 关键词标注：本地词频方案（确定性/离线/零成本，plan.md §3.8）。
/// 角色回复逐词查词典，词频排名超过用户等级阈值且非停用词 → 划线。
public struct KeywordAnnotator: Sendable {
    private let dictionary: DictDatabase

    public init(dictionary: DictDatabase) {
        self.dictionary = dictionary
    }

    /// 返回文本中应划线的小写词集合。
    public func keywords(in text: String, frequencyThreshold: Int) async -> [String] {
        let words = Set(WordTokenizer.tokenize(text).compactMap(\.word))
        var results: [String] = []
        for word in words {
            guard word.count >= 4, !Self.stopwords.contains(word) else { continue }
            guard let entry = await dictionary.lookup(word) else { continue }
            if Self.isRare(entry: entry, threshold: frequencyThreshold) {
                results.append(word)
            }
        }
        return results.sorted()
    }

    /// 词频排名（frq 优先、bnc 兜底；0 表示无数据，视为生僻）超阈值 → 关键词。
    static func isRare(entry: DictEntry, threshold: Int) -> Bool {
        let rank: Int
        switch (entry.frq, entry.bnc) {
        case (0, 0): return true
        case (0, let bnc): rank = bnc
        case (let frq, 0): rank = frq
        case (let frq, let bnc): rank = min(frq, bnc)
        }
        return rank > threshold
    }

    // MARK: - 序列化（keywordRangesJSON）

    private struct Payload: Codable {
        var words: [String]
    }

    public static func encode(words: [String]) -> String? {
        guard !words.isEmpty else { return nil }
        guard let data = try? JSONEncoder().encode(Payload(words: words)) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    public static func decodeWords(fromJSON json: String?) -> Set<String> {
        guard let json, let payload = try? JSONDecoder().decode(Payload.self, from: Data(json.utf8)) else {
            return []
        }
        return Set(payload.words)
    }

    /// 高频功能词，即使词典标记生僻也不划线。
    static let stopwords: Set<String> = [
        "about", "after", "again", "against", "along", "also", "always", "another", "anything",
        "around", "because", "been", "before", "being", "between", "both", "cannot", "could",
        "does", "doing", "down", "during", "each", "either", "even", "ever", "every", "everything",
        "from", "gonna", "gotta", "have", "having", "here", "into", "itself", "just", "like",
        "little", "made", "make", "many", "maybe", "more", "most", "much", "must", "never",
        "nothing", "often", "only", "other", "over", "quite", "rather", "really", "right",
        "same", "should", "since", "some", "something", "sometimes", "soon", "still", "such",
        "sure", "than", "that", "their", "them", "then", "there", "these", "they", "thing",
        "things", "think", "this", "those", "through", "under", "until", "very", "wanna",
        "well", "were", "what", "when", "where", "which", "while", "will", "with", "would",
        "your", "yours",
    ]
}

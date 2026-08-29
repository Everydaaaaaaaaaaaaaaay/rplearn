import CoreKit
import Foundation
import SQLite3

/// 词卡只展示有教学价值的固定搭配，不把普通复合名词误当成短语。
enum DictPhraseDisplayPolicy {
    struct Rank: Comparable {
        let tier: Int
        let patternPriority: Int
        let specificityPenalty: Int
        let wordCount: Int
        let word: String

        static func < (lhs: Self, rhs: Self) -> Bool {
            if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
            if lhs.patternPriority != rhs.patternPriority {
                return lhs.patternPriority < rhs.patternPriority
            }
            if lhs.specificityPenalty != rhs.specificityPenalty {
                return lhs.specificityPenalty < rhs.specificityPenalty
            }
            if lhs.wordCount != rhs.wordCount { return lhs.wordCount < rhs.wordCount }
            return lhs.word < rhs.word
        }
    }

    private static let functionWords: Set<String> = [
        "a", "an", "and", "any", "are", "as", "at", "be", "been", "being", "but",
        "by", "can", "could", "for", "from",
        "he", "her", "hers", "him", "his", "i", "if", "in", "into", "is", "it", "its",
        "may", "me", "might", "must", "my", "nor", "not", "of", "on", "or", "our",
        "ours", "shall", "she", "should", "some", "than", "that", "the", "their", "theirs",
        "them", "these", "they", "this", "those", "through", "to", "us", "was", "we",
        "were", "what", "when", "where", "which", "while", "who", "whom", "whose", "will",
        "with", "would", "you", "your", "yours",
    ]

    private static let complementWords: Set<String> = [
        "about", "after", "against", "as", "at", "by", "for", "from", "in", "into", "of",
        "on", "onto", "over", "through", "to", "upon", "with", "without",
    ]

    private static let phrasalParticles: Set<String> = [
        "apart", "around", "away", "back", "down", "forth", "forward", "off", "out", "over",
        "together", "up",
    ]

    private static let placeholderWords: Set<String> = [
        "doing", "oneself", "sb", "somebody", "someone", "something", "sth",
    ]

    private static let beForms: Set<String> = ["be", "been", "being", "is", "are", "was", "were"]

    private static let preferredPatternOrder: [String: Int] = [
        "out": 0, "up": 1, "off": 2, "away": 3, "back": 4, "down": 5,
        "over": 6, "around": 7, "apart": 8, "together": 9,
    ]

    static func allowsPhraseDiscovery(for selectedWord: String) -> Bool {
        let selectedTokens = tokens(in: selectedWord)
        return selectedTokens.count == 1 && !functionWords.contains(selectedTokens[0])
    }

    static func rank(
        phrase: String,
        selectedWord: String,
        isOxford: Bool,
        selectedEntry: DictEntry?
    ) -> Rank? {
        let phraseTokens = tokens(in: phrase)
        let selectedTokens = tokens(in: selectedWord)
        guard allowsPhraseDiscovery(for: selectedWord),
              phraseTokens.count >= 2,
              selectedTokens.count == 1,
              let selectedIndex = phraseTokens.firstIndex(of: selectedTokens[0])
        else { return nil }

        let labels = Set(selectedEntry?.meaningGroups.compactMap(\.partOfSpeech) ?? [])
        let isVerb = !labels.isDisjoint(with: ["动词", "及物动词", "不及物动词"])
            || selectedEntry?.senses.contains(where: { $0.partOfSpeech == "v" }) == true
        let isAdjective = labels.contains("形容词")
            || selectedEntry?.senses.contains(where: { ["a", "s"].contains($0.partOfSpeech) }) == true
        guard isVerb || isAdjective else { return nil }

        let auxiliaryLed = selectedIndex == 1
            && beForms.contains(phraseTokens[0])
            && isAdjective
        guard selectedIndex == 0 || auxiliaryLed else { return nil }

        let nextIndex = selectedIndex + 1
        let nextWord = phraseTokens.indices.contains(nextIndex) ? phraseTokens[nextIndex] : nil
        let placeholderCount = phraseTokens.filter(placeholderWords.contains).count
        let isOxfordPattern = isOxford && phraseTokens.count <= 4
        let isAuxiliaryAdjectivePattern = auxiliaryLed
            && nextWord.map(complementWords.contains) == true
            && phraseTokens.count <= 5
        let isComplexVerbFrame = isVerb
            && nextWord.map(placeholderWords.contains) == true
            && phraseTokens.dropFirst(nextIndex + 1).contains(where: complementWords.contains)
            && phraseTokens.count <= 6
        let isPhrasalVerb = isVerb
            && nextWord.map(phrasalParticles.contains) == true
            && phraseTokens.count <= 4

        let tier: Int
        if isOxfordPattern {
            tier = 0
        } else if isAuxiliaryAdjectivePattern {
            tier = 1
        } else if isComplexVerbFrame {
            tier = 2
        } else if isPhrasalVerb {
            tier = 3
        } else {
            return nil
        }

        return Rank(
            tier: tier,
            patternPriority: nextWord.flatMap { preferredPatternOrder[$0] } ?? 100,
            specificityPenalty: -placeholderCount,
            wordCount: phraseTokens.count,
            word: phrase.lowercased()
        )
    }

    static func deduplicated(_ entries: [DictEntry]) -> [DictEntry] {
        var order: [String] = []
        var bestByKey: [String: DictEntry] = [:]
        for entry in entries {
            let key = deduplicationKey(for: entry.word)
            if bestByKey[key] == nil {
                order.append(key)
                bestByKey[key] = entry
            } else if specificity(of: entry.word) > specificity(of: bestByKey[key]?.word ?? "") {
                bestByKey[key] = entry
            }
        }
        return order.compactMap { bestByKey[$0] }
    }

    private static func deduplicationKey(for phrase: String) -> String {
        var values = tokens(in: phrase).map { token -> String in
            switch token {
            case "sb", "somebody", "someone": "<person>"
            case "sth", "something": "<thing>"
            default: token
            }
        }
        if values.first == "be", values.count > 2 {
            values.removeFirst()
        }
        while let last = values.last,
              ["<person>", "<thing>", "oneself"].contains(last) {
            values.removeLast()
        }
        return values.joined(separator: " ")
    }

    private static func specificity(of phrase: String) -> Int {
        let values = tokens(in: phrase)
        return values.filter(placeholderWords.contains).count * 100 + values.count
    }

    private static func tokens(in text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map {
                String($0).trimmingCharacters(
                    in: .punctuationCharacters.union(.symbols)
                )
            }
            .filter { !$0.isEmpty }
    }
}

/// 全量 ECDICT + WordNet 只读查询（原生 sqlite3，预编译语句复用）。
/// 查询流水线：word 精确 → lemma 反查 → 规则回退 → 未收录；上下文短语单独作为建议返回。
public actor DictDatabase {
    public enum DictError: Error {
        case cannotOpen(String)
        case prepareFailed(String)
    }

    /// 持有 sqlite 句柄并在自身 deinit 里统一释放（actor 的 deinit 不能访问非 Sendable 属性）。
    /// sqlite 连接非线程安全，但所有访问都经由 actor 序列化，故 @unchecked Sendable 成立。
    private final class Connection: @unchecked Sendable {
        let db: OpaquePointer
        let exactStatement: OpaquePointer
        let lemmaStatement: OpaquePointer
        let prefixStatement: OpaquePointer
        let relatedPhraseStatement: OpaquePointer
        let senseStatement: OpaquePointer

        init(databaseURL: URL) throws {
            var handle: OpaquePointer?
            let result = sqlite3_open_v2(databaseURL.path, &handle, SQLITE_OPEN_READONLY, nil)
            guard result == SQLITE_OK, let handle else {
                sqlite3_close(handle)
                throw DictError.cannotOpen("sqlite3_open_v2 failed (\(result)) at \(databaseURL.path)")
            }

            func prepare(_ sql: String) throws -> OpaquePointer {
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                    sqlite3_close(handle)
                    throw DictError.prepareFailed(sql)
                }
                return statement
            }

            db = handle
            exactStatement = try prepare(
                "SELECT word, phonetic, definition, translation, pos, collins, oxford, tag, bnc, frq, exchange FROM word WHERE wl = ?"
            )
            lemmaStatement = try prepare("SELECT lemma FROM lemma WHERE form = ?")
            prefixStatement = try prepare("SELECT word FROM word WHERE wl >= ? AND wl < ? ORDER BY wl LIMIT ?")
            relatedPhraseStatement = try prepare(
                "SELECT word, oxford FROM word WHERE wl >= ? AND wl < ? ORDER BY wl LIMIT ?"
            )
            senseStatement = try prepare(
                "SELECT rank, pos, definition, examples, synonyms FROM sense WHERE wl = ? ORDER BY rank, pos LIMIT 12"
            )
        }

        deinit {
            sqlite3_finalize(exactStatement)
            sqlite3_finalize(lemmaStatement)
            sqlite3_finalize(prefixStatement)
            sqlite3_finalize(relatedPhraseStatement)
            sqlite3_finalize(senseStatement)
            sqlite3_close(db)
        }
    }

    private let connection: Connection

    public init(databaseURL: URL) throws {
        connection = try Connection(databaseURL: databaseURL)
    }

    // MARK: - 查询

    /// 完整查询流水线。返回命中的词条；未收录返回 nil（UI 层走 LLM 简释兜底）。
    public func lookup(_ rawWord: String) -> DictEntry? {
        let word = rawWord.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return nil }

        if let entry = exactEntry(word) {
            if isPureInflection(entry) {
                for lemma in lemmas(of: word) {
                    if let lemmaEntry = exactEntry(lemma) {
                        return lemmaEntry
                    }
                }
            }
            return entry
        }
        for lemma in lemmas(of: word) {
            if let entry = exactEntry(lemma) {
                return entry
            }
        }
        for candidate in WordFormRules.candidates(for: word) {
            if let entry = exactEntry(candidate) {
                return entry
            }
        }
        return nil
    }

    /// 返回原句中确实收录的短语，由 UI 作为建议展示，不擅自替换被点单词的主释义。
    public func matchingPhrases(
        _ rawCandidates: [String],
        excluding rawWord: String,
        limit: Int = 4
    ) -> [DictEntry] {
        let excluded = rawWord.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let displayLimit = min(max(limit, 0), 4)
        guard displayLimit > 0,
              DictPhraseDisplayPolicy.allowsPhraseDiscovery(for: excluded)
        else { return [] }
        let selectedEntry = lookup(excluded)
        var results: [DictEntry] = []
        var seen = Set<String>()
        for candidate in rawCandidates {
            let normalized = candidate.lowercased()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalized != excluded,
                  seen.insert(normalized).inserted,
                  let entry = exactEntry(normalized),
                  DictPhraseDisplayPolicy.rank(
                      phrase: entry.word,
                      selectedWord: excluded,
                      isOxford: entry.oxford,
                      selectedEntry: selectedEntry
                  ) != nil
            else { continue }
            results.append(entry)
            if results.count == displayLimit { break }
        }
        return Array(
            DictPhraseDisplayPolicy.deduplicated(results).prefix(displayLimit)
        )
    }

    /// 返回以当前词开头、具备教学价值的固定搭配；普通复合名词不会进入词卡。
    public func relatedPhrases(for rawWord: String, limit: Int = 4) -> [DictEntry] {
        let word = rawWord.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let displayLimit = min(max(limit, 0), 4)
        guard !word.isEmpty,
              displayLimit > 0,
              DictPhraseDisplayPolicy.allowsPhraseDiscovery(for: word)
        else { return [] }
        let selectedEntry = lookup(word)

        let prefix = word + " "
        let statement = connection.relatedPhraseStatement
        defer { sqlite3_reset(statement) }
        bindText(prefix, statement: statement, index: 1)
        bindText(prefix + "\u{FFFF}", statement: statement, index: 2)
        let scanLimit = min(max(displayLimit * 256, 256), 1024)
        sqlite3_bind_int(statement, 3, Int32(scanLimit))

        var rankedWords: [(rank: DictPhraseDisplayPolicy.Rank, word: String)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let phrase = columnText(statement, 0),
                  let rank = DictPhraseDisplayPolicy.rank(
                      phrase: phrase,
                      selectedWord: word,
                      isOxford: sqlite3_column_int(statement, 1) == 1,
                      selectedEntry: selectedEntry
                  )
            else { continue }
            rankedWords.append((rank, phrase))
        }
        let candidates = rankedWords
            .sorted { $0.rank < $1.rank }
            .prefix(displayLimit * 4)
            .compactMap { exactEntry($0.word.lowercased()) }
        return Array(
            DictPhraseDisplayPolicy.deduplicated(candidates).prefix(displayLimit)
        )
    }

    /// 精确命中（入参需已 lowercase）。
    public func exactEntry(_ wl: String) -> DictEntry? {
        let statement = connection.exactStatement
        defer { sqlite3_reset(statement) }
        bindText(wl, statement: statement, index: 1)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return DictEntry(
            word: columnText(statement, 0) ?? wl,
            phonetic: columnText(statement, 1),
            definition: columnText(statement, 2),
            translation: columnText(statement, 3),
            pos: columnText(statement, 4),
            collins: Int(sqlite3_column_int(statement, 5)),
            oxford: sqlite3_column_int(statement, 6) == 1,
            tag: columnText(statement, 7),
            bnc: Int(sqlite3_column_int(statement, 8)),
            frq: Int(sqlite3_column_int(statement, 9)),
            exchange: columnText(statement, 10),
            senses: senses(for: wl)
        )
    }

    private func senses(for word: String) -> [DictSense] {
        let statement = connection.senseStatement
        defer { sqlite3_reset(statement) }
        bindText(word, statement: statement, index: 1)
        var results: [DictSense] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let partOfSpeech = columnText(statement, 1),
                  let definition = columnText(statement, 2)
            else { continue }
            results.append(
                DictSense(
                    rank: Int(sqlite3_column_int(statement, 0)),
                    partOfSpeech: partOfSpeech,
                    definition: definition,
                    examples: decodeStringArray(columnText(statement, 3)),
                    synonyms: decodeStringArray(columnText(statement, 4))
                )
            )
        }
        return results
    }

    /// lemma 反查（looked → [look]）。
    public func lemmas(of form: String) -> [String] {
        let statement = connection.lemmaStatement
        defer { sqlite3_reset(statement) }
        bindText(form, statement: statement, index: 1)
        var results: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let lemma = columnText(statement, 0) {
                results.append(lemma)
            }
        }
        return results
    }

    /// 前缀联想（搜索提示用）。
    public func suggestions(prefix rawPrefix: String, limit: Int = 10) -> [String] {
        let prefix = rawPrefix.lowercased().trimmingCharacters(in: .whitespaces)
        guard !prefix.isEmpty else { return [] }
        let statement = connection.prefixStatement
        defer { sqlite3_reset(statement) }
        bindText(prefix, statement: statement, index: 1)
        bindText(prefix + "\u{FFFF}", statement: statement, index: 2)
        sqlite3_bind_int(statement, 3, Int32(limit))
        var results: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let word = columnText(statement, 0) {
                results.append(word)
            }
        }
        return results
    }

    // MARK: - sqlite 辅助

    private func columnText(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard let cString = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: cString)
    }

    private func bindText(_ value: String, statement: OpaquePointer, index: Int32) {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, index, value, -1, transient)
    }

    private func decodeStringArray(_ value: String?) -> [String] {
        guard let value,
              let data = value.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return decoded
    }

    /// 全量 ECDICT 会把 went/looked 等词形也作为独立词条收录。
    /// 只有当释义仅是一行词形说明时才回到原形；left/saw 等兼有独立词义的词不受影响。
    private func isPureInflection(_ entry: DictEntry) -> Bool {
        guard entry.translationLines.count == 1,
              let translation = entry.translationLines.first
        else { return false }
        return ["过去式", "过去分词", "现在分词", "复数形式", "第三人称单数"]
            .contains { translation.contains($0) }
    }
}

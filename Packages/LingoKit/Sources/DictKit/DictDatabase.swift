import CoreKit
import Foundation
import SQLite3

/// 词卡只展示有教学价值的固定搭配，不把普通复合名词误当成短语。
enum DictPhraseDisplayPolicy {
    struct Rank: Comparable {
        let tier: Int
        let linkPriority: Int
        let wordCount: Int
        let word: String

        static func < (lhs: Self, rhs: Self) -> Bool {
            if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
            if lhs.linkPriority != rhs.linkPriority {
                return lhs.linkPriority < rhs.linkPriority
            }
            if lhs.wordCount != rhs.wordCount { return lhs.wordCount < rhs.wordCount }
            return lhs.word < rhs.word
        }
    }

    private static let linkWords: Set<String> = [
        "about", "above", "across", "after", "against", "along", "around", "as", "at",
        "away", "back", "before", "behind", "between", "by", "down", "for", "forth",
        "forward", "from", "in", "into", "of", "off", "on", "onto", "out", "over",
        "through", "to", "together", "under", "up", "upon", "with", "without",
    ]

    private static let placeholderWords: Set<String> = [
        "doing", "oneself", "sb", "somebody", "someone", "something", "sth",
    ]

    private static let preferredLinkOrder: [String: Int] = [
        "with": 0, "at": 1, "about": 2, "for": 3, "to": 4, "from": 5,
        "of": 6, "on": 7, "in": 8, "into": 9, "out": 10, "up": 11,
        "down": 12, "off": 13, "over": 14, "against": 15, "away": 16,
    ]

    static func rank(
        phrase: String,
        selectedWord: String,
        isOxford: Bool
    ) -> Rank? {
        let phraseTokens = tokens(in: phrase)
        let selectedTokens = tokens(in: selectedWord)
        guard phraseTokens.count >= 2,
              !selectedTokens.isEmpty,
              selectedTokens.allSatisfy(phraseTokens.contains)
        else { return nil }

        let selectedIndex = selectedTokens.count == 1
            ? phraseTokens.firstIndex(of: selectedTokens[0])
            : nil
        let adjacentLink = selectedIndex.flatMap { index -> String? in
            let next = index + 1
            guard phraseTokens.indices.contains(next), linkWords.contains(phraseTokens[next])
            else { return nil }
            return phraseTokens[next]
        }
        let firstLink = adjacentLink ?? phraseTokens.first(where: linkWords.contains)
        let hasPlaceholder = phraseTokens.contains(where: placeholderWords.contains)

        let tier: Int
        if isOxford {
            tier = 0
        } else if adjacentLink != nil {
            tier = 1
        } else if hasPlaceholder {
            tier = 2
        } else if firstLink != nil {
            tier = 3
        } else {
            return nil
        }

        return Rank(
            tier: tier,
            linkPriority: firstLink.flatMap { preferredLinkOrder[$0] } ?? 100,
            wordCount: phraseTokens.count,
            word: phrase.lowercased()
        )
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
        guard displayLimit > 0 else { return [] }
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
                      isOxford: entry.oxford
                  ) != nil
            else { continue }
            results.append(entry)
            if results.count == displayLimit { break }
        }
        return results
    }

    /// 返回以当前词开头、具备教学价值的固定搭配；普通复合名词不会进入词卡。
    public func relatedPhrases(for rawWord: String, limit: Int = 4) -> [DictEntry] {
        let word = rawWord.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let displayLimit = min(max(limit, 0), 4)
        guard !word.isEmpty, displayLimit > 0 else { return [] }

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
                      isOxford: sqlite3_column_int(statement, 1) == 1
                  )
            else { continue }
            rankedWords.append((rank, phrase))
        }
        return rankedWords
            .sorted { $0.rank < $1.rank }
            .prefix(displayLimit)
            .compactMap { exactEntry($0.word.lowercased()) }
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

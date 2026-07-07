import CoreKit
import Foundation
import SQLite3

/// ECDICT 只读查询（原生 sqlite3，预编译语句复用）。
/// 查询流水线：lowercase → word 精确 → lemma 反查 → 规则回退 → 未收录。
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
        }

        deinit {
            sqlite3_finalize(exactStatement)
            sqlite3_finalize(lemmaStatement)
            sqlite3_finalize(prefixStatement)
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
            exchange: columnText(statement, 10)
        )
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
}

import Foundation
import Testing
@testable import DictKit

/// 对打进 App bundle 的真实 ecdict_lite.sqlite 做集成查询（测试由 LingoTrip 托管，Bundle.main 即 App）。
@Suite("DictDatabase 查询流水线")
struct DictDatabaseTests {
    private func openDatabase() throws -> DictDatabase {
        let url = try #require(Bundle.main.url(forResource: "ecdict_lite", withExtension: "sqlite"))
        return try DictDatabase(databaseURL: url)
    }

    @Test("精确命中")
    func exactHit() async throws {
        let db = try openDatabase()
        let entry = await db.lookup("look")
        #expect(entry?.word == "look")
        #expect(entry?.translation?.isEmpty == false)
        #expect(entry?.phonetic?.isEmpty == false)
    }

    @Test("大小写不敏感")
    func caseInsensitive() async throws {
        let db = try openDatabase()
        #expect(await db.lookup("Look")?.word == "look")
        #expect(await db.lookup("BEAUTIFUL") != nil)
    }

    @Test("lemma 表还原不规则变形")
    func irregularLemma() async throws {
        let db = try openDatabase()
        #expect(await db.lookup("went")?.word == "go")
        #expect(await db.lookup("ran")?.word == "run")
    }

    @Test("规则回退还原规则变形")
    func ruleFallback() async throws {
        let db = try openDatabase()
        // looked 在 lemma 表（由 exchange 展开）或规则回退中至少一条路径可达 look
        #expect(await db.lookup("looked")?.word == "look")
    }

    @Test("未收录词返回 nil")
    func missingWord() async throws {
        let db = try openDatabase()
        #expect(await db.lookup("zzzzunfindable") == nil)
        #expect(await db.lookup("") == nil)
    }

    @Test("前缀联想")
    func prefixSuggestions() async throws {
        let db = try openDatabase()
        let suggestions = await db.suggestions(prefix: "beauti", limit: 5)
        #expect(!suggestions.isEmpty)
        #expect(suggestions.allSatisfy { $0.lowercased().hasPrefix("beauti") })
    }
}

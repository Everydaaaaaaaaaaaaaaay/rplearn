import Foundation
import Testing
@testable import DictKit

/// 对打进 App bundle 的全量本地学习词典做集成查询（测试由 LingoTrip 托管）。
@Suite("DictDatabase 查询流水线")
struct DictDatabaseTests {
    private func openDatabase() throws -> DictDatabase {
        let url = try #require(Bundle.main.url(forResource: "learner_dictionary", withExtension: "sqlite"))
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

    @Test("全量库覆盖旧精简规则遗漏的新常用词")
    func expandedCoverage() async throws {
        let db = try openDatabase()
        #expect(await db.lookup("staycation")?.translationLines.contains("n. 居家度假") == true)
        #expect(await db.lookup("influencer")?.translation?.isEmpty == false)
        #expect(await db.lookup("underwhelming")?.translation?.isEmpty == false)
    }

    @Test("WordNet 提供按词性排序的英文义项与本地例句")
    func structuredLearningSenses() async throws {
        let db = try openDatabase()
        let entry = try #require(await db.lookup("run"))

        #expect(entry.senses.count >= 4)
        #expect(Set(entry.senses.map(\.partOfSpeech)).isSuperset(of: ["n", "v"]))
        #expect(entry.senses.contains { !$0.examples.isEmpty })
        #expect(entry.senses.allSatisfy { !$0.definition.isEmpty })
    }

    @Test("原句候选返回固定搭配但不覆盖单词主释义")
    func phraseCandidatesAreSuggestions() async throws {
        let db = try openDatabase()
        let word = await db.lookup("break")
        let phrases = await db.matchingPhrases(
            ["use a break from", "a break from", "break from"],
            excluding: "break"
        )
        #expect(word?.word.lowercased() == "break")
        #expect(phrases.map { $0.word.lowercased() }.contains("break from"))
    }

    @Test("中文释义按词性拆分且词形可继续查询")
    func learningFieldsAreStructured() async throws {
        let db = try openDatabase()
        let fine = try #require(await db.lookup("fine"))
        let go = try #require(await db.lookup("go"))

        #expect(fine.meaningGroups.contains { $0.partOfSpeech == "名词" })
        #expect(fine.meaningGroups.contains { $0.partOfSpeech == "形容词" })
        #expect(go.wordForms.contains { $0.label == "过去式" && $0.word == "went" })
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

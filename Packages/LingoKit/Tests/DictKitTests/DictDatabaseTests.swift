import Foundation
import Testing
@testable import DictKit

private actor TranslationInvocationCounter {
    private var value = 0

    func increment() {
        value += 1
    }

    func count() -> Int {
        value
    }
}

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

    @Test("同一词性的多个英文义项合并并用分号分隔")
    func repeatedPartsOfSpeechAreGrouped() {
        let senses = [
            DictSense(rank: 1, partOfSpeech: "n", definition: "noun", examples: [], synonyms: []),
            DictSense(
                rank: 1,
                partOfSpeech: "v",
                definition: "  first   verb ",
                examples: ["first example"],
                synonyms: ["make"]
            ),
            DictSense(
                rank: 2,
                partOfSpeech: "v",
                definition: "second verb",
                examples: ["second example"],
                synonyms: ["make", "prepare"]
            ),
            DictSense(rank: 1, partOfSpeech: "a", definition: "adjective", examples: [], synonyms: []),
        ]

        let groups = DictSenseDisplayPolicy.groups(for: senses)

        #expect(groups.map(\.partOfSpeech) == ["n", "v", "a"])
        #expect(groups[1].definitionText == "first verb; second verb")
        #expect(groups[1].synonymText == "≈ make · prepare")
    }

    @Test("英文回退释义恢复续行并把词性显示为中文")
    func fallbackEnglishDefinitionsAreStructured() {
        let groups = DictSenseDisplayPolicy.fallbackGroups(
            for: [
                "pron. Which (of two); which one (of two); -- used",
                "   interrogatively and relatively.",
                "conj. In case; if; -- used to introduce alternatives",
                "   connected by or or whether.",
            ]
        )

        #expect(groups.map(\.partOfSpeechLabel) == ["代词", "连词"])
        #expect(
            groups[0].definitionText
                == "Which (of two); which one (of two); -- used interrogatively and relatively."
        )
        #expect(!groups.map(\.definitionText).joined().contains("#"))
    }

    @Test("例句翻译忽略空输入并清理译文首尾空白")
    func exampleTranslationActionsNormalizeOutput() async {
        let actions = DictExampleTranslationActions { request in
            DictExampleTranslation(
                sentenceZh: "  \(request.sentence)的自然中文翻译  ",
                meaningZh: "  合适的  "
            )
        }
        let request = DictExampleTranslationRequest(
            sentence: "  Fancy a pint later?  ",
            word: "fancy",
            partOfSpeechAbbreviation: "v.",
            fallbackMeaningZh: "想要"
        )

        let translated = await actions.translate(request)
        #expect(translated?.sentenceZh == "Fancy a pint later?的自然中文翻译")
        #expect(translated?.meaningZh == "合适的")
        #expect(
            await actions.translate(
                DictExampleTranslationRequest(
                    sentence: "   \n ",
                    word: "fancy",
                    partOfSpeechAbbreviation: "v."
                )
            ) == nil
        )
    }

    @Test("例句括号内拒绝英文词义并回退到本地中文词义")
    func exampleTranslationMeaningMustRemainChinese() async {
        let actions = DictExampleTranslationActions { _ in
            DictExampleTranslation(
                sentenceZh: "本周找个时间喝一杯正经的啤酒怎么样？",
                meaningZh: "marked by suitability"
            )
        }
        let request = DictExampleTranslationRequest(
            sentence: "Fancy a proper pint sometime this week?",
            word: "proper",
            partOfSpeechAbbreviation: "adj.",
            definitionEn: "marked by suitability",
            fallbackMeaningZh: "合适的"
        )

        let translated = await actions.translate(request)

        #expect(translated?.meaningZh == "合适的")
    }

    @Test("相同例句的并发翻译合并为一次请求并复用缓存")
    func exampleTranslationCacheDeduplicatesRequests() async {
        let cache = DictExampleTranslationCache()
        let counter = TranslationInvocationCounter()
        let actions = DictExampleTranslationActions { request in
            await counter.increment()
            try? await Task.sleep(for: .milliseconds(20))
            return DictExampleTranslation(
                sentenceZh: "译：\(request.sentence)",
                meaningZh: "问候"
            )
        }
        let request = DictExampleTranslationRequest(
            sentence: "How are you?",
            word: "how",
            partOfSpeechAbbreviation: "adv.",
            fallbackMeaningZh: "怎样"
        )

        async let first = cache.translation(for: request, using: actions)
        async let second = cache.translation(for: request, using: actions)
        let results = await (first, second)
        let cached = await cache.translation(for: request, using: actions)

        #expect(results.0?.sentenceZh == "译：How are you?")
        #expect(results.1?.sentenceZh == "译：How are you?")
        #expect(cached?.sentenceZh == "译：How are you?")
        #expect(await counter.count() == 1)
    }

    @Test("例句优先保留当前语境并按词性适量分组")
    func usageExamplesCoverContextAndPartsOfSpeech() {
        let entry = DictEntry(
            word: "test",
            translation: "n. 测试\\nv. 检验",
            senses: [
                DictSense(
                    rank: 1,
                    partOfSpeech: "n",
                    definition: "an examination",
                    examples: ["The test starts at nine."],
                    synonyms: []
                ),
                DictSense(
                    rank: 1,
                    partOfSpeech: "v",
                    definition: "to examine",
                    examples: ["They test the alarm every week."],
                    synonyms: []
                ),
            ]
        )

        let groups = DictUsageExamplePolicy.groups(
            for: entry,
            requestedWord: "test",
            contextText: "We can test it after lunch. This sentence is unrelated."
        )

        #expect(groups.map(\.partOfSpeechLabel) == ["动词", "名词"])
        #expect(groups[0].examples.map(\.text) == [
            "We can test it after lunch.",
            "They test the alarm every week.",
        ])
        #expect(groups[0].examples.allSatisfy { $0.annotation == "（v. 检验）" })
        #expect(groups[1].examples.map(\.text) == ["The test starts at nine."])
        #expect(groups[1].examples.first?.annotation == "（n. 测试）")
    }

    @Test("WordNet 动词例句匹配 ECDICT 及物动词释义且不回退到名词")
    func verbExamplesUseCompatibleVerbMeaning() {
        let entry = DictEntry(
            word: "tube",
            translation: "n. 管, 软管, 隧道\\nvt. 把...装管, 使通过管子",
            senses: [
                DictSense(
                    rank: 1,
                    partOfSpeech: "n",
                    definition: "a hollow cylindrical object",
                    examples: ["The tube is made of glass."],
                    synonyms: []
                ),
                DictSense(
                    rank: 2,
                    partOfSpeech: "v",
                    definition: "convey in a tube",
                    examples: ["Inside Paris, they used to tube mail."],
                    synonyms: []
                ),
            ]
        )

        let groups = DictUsageExamplePolicy.groups(
            for: entry,
            requestedWord: "tube",
            contextText: nil
        )
        let verbGroup = groups.first { $0.partOfSpeechLabel == "动词" }

        #expect(verbGroup?.examples.first?.annotation == "（v. 把...装管）")
        #expect(verbGroup?.examples.contains { $0.annotation == "（v. 管）" } == false)
        #expect(DictPartOfSpeechDisplay.labelsAreCompatible("动词", "及物动词"))
        #expect(DictPartOfSpeechDisplay.labelsAreCompatible("动词", "不及物动词"))
        #expect(!DictPartOfSpeechDisplay.labelsAreCompatible("动词", "名词"))
    }

    @Test("同一词性存在多个义项时只以英文义项作为翻译上下文，不直接显示英文")
    func examplesKeepSenseDefinitionAsTranslationContext() async throws {
        let db = try openDatabase()
        let entry = try #require(await db.lookup("tube"))

        let groups = DictUsageExamplePolicy.groups(
            for: entry,
            requestedWord: "tube",
            contextText: nil
        )
        let verbExamples = try #require(
            groups.first { $0.partOfSpeechLabel == "动词" }?.examples
        )

        #expect(verbExamples.allSatisfy { $0.annotation == "（v. 把...装管）" })
        #expect(verbExamples.map(\.definitionEn).contains("convey in a tube"))
        #expect(
            verbExamples.map(\.definitionEn)
                .contains("ride or float on an inflated tube")
        )
        #expect(!verbExamples.map(\.annotation).joined().contains("convey in a tube"))
    }

    @Test("单一词性无论义项多少最多显示两条例句")
    func usageExamplesAreLimitedPerPartOfSpeech() {
        let entry = DictEntry(
            word: "overwhelming",
            translation: "adj. 压倒性的, 无法抵抗的",
            senses: [
                DictSense(
                    rank: 1,
                    partOfSpeech: "a",
                    definition: "very intense",
                    examples: ["An overwhelming need for solitude."],
                    synonyms: []
                ),
                DictSense(
                    rank: 2,
                    partOfSpeech: "a",
                    definition: "very large",
                    examples: ["They won an overwhelming majority."],
                    synonyms: []
                ),
                DictSense(
                    rank: 3,
                    partOfSpeech: "a",
                    definition: "hard to resist",
                    examples: ["She felt overwhelming joy."],
                    synonyms: []
                ),
            ]
        )

        let groups = DictUsageExamplePolicy.groups(
            for: entry,
            requestedWord: "overwhelming",
            contextText: "London can be overwhelming on day one."
        )

        #expect(groups.count == 1)
        #expect(groups[0].examples.count == 2)
        #expect(groups[0].examples.map(\.text) == [
            "London can be overwhelming on day one.",
            "An overwhelming need for solitude.",
        ])
        #expect(groups[0].examples.map(\.annotation) == [
            "（adj. 压倒性的）",
            "（adj. 压倒性的）",
        ])
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

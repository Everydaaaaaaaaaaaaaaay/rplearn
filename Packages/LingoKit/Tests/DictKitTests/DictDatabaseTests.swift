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

    @Test("目标词完整匹配，不允许近义词或子串，保留已知不规则词形")
    func examplesMatchTheActualHeadword() {
        let just = DictEntry(word: "just")
        #expect(!DictUsageExamplePolicy.containsTarget("I was merely asking.", entry: just))
        #expect(!DictUsageExamplePolicy.containsTarget("It is simply a matter of time.", entry: just))
        #expect(!DictUsageExamplePolicy.containsTarget("We need justice.", entry: just))
        #expect(DictUsageExamplePolicy.containsTarget("I've JUST arrived.", entry: just))
        #expect(DictUsageExamplePolicy.containsTarget("She went home.", entry: DictEntry(word: "go", exchange: "p:went/d:gone")))
        #expect(!DictUsageExamplePolicy.containsTarget("The window is open.", entry: DictEntry(word: "in")))
    }

    @Test("随包高频词补充可查询、用法不同且来源独立", arguments: ["which", "what", "who", "whom", "whose", "where", "when", "why", "how", "because", "although", "though", "if", "unless", "whether", "while", "since", "until", "before", "after", "than", "that", "this", "these", "those", "each", "every", "either", "neither", "both", "any", "some", "another", "other", "such", "only", "even", "also", "just", "yet"])
    func learnerExampleCoverage(word: String) async throws {
        let db = try openDatabase()
        let entry = try #require(await db.lookup(word))
        let examples = DictUsageExamplePolicy.groups(for: entry).flatMap(\.examples)
        let added = examples.filter { $0.dictionarySource == "lingotrip-learner-examples" }
        #expect(added.count == 2)
        #expect(Set(added.map(\.senseID)).count == 2)
        #expect(examples.allSatisfy { DictUsageExamplePolicy.containsTarget($0.text, entry: entry) })
        #expect(!examples.contains { $0.text == "I was merely asking" || $0.text == "it is simply a matter of time" })
    }

    @Test("toasties 是烤三明治的复数，不能回到形容词 toasty")
    func toastiePlural() async throws {
        let db = try openDatabase()
        #expect(await db.lookup("toasties")?.word == "toastie")
        #expect(await db.lookup("toastie")?.translation?.contains("烤三明治") == true)
        #expect(await db.lookup("toasty")?.exchange == nil)
        #expect(await db.lookup("toast")?.translation?.contains("烤面包") == true)
        #expect(WordFormRules.candidates(for: "toasties").first == "toastie")
    }

    @Test("精确命中")
    func exactHit() async throws {
        let db = try openDatabase()
        let entry = await db.lookup("look")
        #expect(entry?.word == "look")
        #expect(entry?.translation?.isEmpty == false)
        #expect(entry?.phonetic?.isEmpty == false)
    }

    @Test("压缩词头仍保留普通词与原始大小写")
    func compactWordStoragePreservesDisplaySpelling() async throws {
        let db = try openDatabase()

        #expect(await db.lookup("look")?.word == "look")
        #expect(await db.lookup("7-eleven")?.word == "7-Eleven")
        #expect(await db.suggestions(prefix: "look", limit: 3).first == "look")
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

    @Test("同一词性的多个英文义项用分号加换行分隔")
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
        #expect(groups[1].definitionLines == ["first verb", "second verb"])
        #expect(groups[1].definitionText == "first verb;\nsecond verb")
        #expect(groups[1].synonymText == "≈ make · prepare")
    }

    @Test("中文释义只按顶层中英文逗号和分号拆分")
    func topLevelMeaningSplitPreservesNestedParentheses() {
        #expect(
            DictDisplayText.splitTopLevelMeanings("配偶, 对手，助手；（象棋，将死）")
                == ["配偶", "对手", "助手", "（象棋，将死）"]
        )
        #expect(
            DictDisplayText.splitTopLevelMeanings("A（内，含）；B (x, y), C")
                == ["A（内，含）", "B (x, y)", "C"]
        )
    }

    @Test("mate 例句在多义名词翻译完成前只显示词性")
    func mateExamplesDoNotDisplayAllNounMeanings() {
        let entry = DictEntry(
            word: "mate",
            translation: "n. 配偶, 对手, 助手, （象棋，将死）",
            senses: [
                DictSense(
                    rank: 1,
                    partOfSpeech: "n",
                    definition: "a fellow member of a team",
                    examples: ["He was my first mate."],
                    synonyms: []
                ),
                DictSense(
                    rank: 2,
                    partOfSpeech: "n",
                    definition: "a spouse",
                    examples: ["She introduced her mate."],
                    synonyms: []
                ),
            ]
        )

        let examples = DictUsageExamplePolicy.groups(
            for: entry
        ).flatMap(\.examples)

        #expect(examples.count == 2)
        #expect(examples.allSatisfy { $0.annotation == "（n.）" })
        #expect(examples.allSatisfy { $0.candidateMeaningsZhHans == ["配偶", "对手", "助手", "（象棋，将死）"] })
        #expect(examples.allSatisfy { $0.senseID != nil && $0.lemma == "mate" && $0.partOfSpeech == "n" })
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
            DictExampleTranslation(sentenceZh: "  \(request.sentence)的自然中文翻译  ")
        }
        let request = DictExampleTranslationRequest(sentence: "  Fancy a pint later?  ")

        let translated = await actions.translate(request)
        #expect(translated?.sentenceZh == "Fancy a pint later?的自然中文翻译")
        #expect(
            await actions.translate(
                DictExampleTranslationRequest(sentence: "   \n ")
            ) == nil
        )

        let contextual = await DictExampleTranslationActions { _ in
            DictExampleTranslation(
                sentenceZhHans: "  这是译文。 ",
                contextualMeaningZhHans: "  配偶  "
            )
        }.translate(DictExampleTranslationRequest(sentence: "Mate."))
        #expect(contextual?.sentenceZhHans == "这是译文。")
        #expect(contextual?.contextualMeaningZhHans == "配偶")
    }

    @Test("服务端例句翻译失败时只用系统翻译补齐整句")
    func exampleTranslationActionsFallBackToSystemSentenceTranslation() async {
        let fallback = DictExampleTranslationActions { _ in nil }
            .fallingBackToSentenceTranslation { sentence in
                sentence == "Fancy a coffee?" ? "想喝杯咖啡吗？" : nil
            }

        let translated = await fallback.translate(
            DictExampleTranslationRequest(sentence: "Fancy a coffee?")
        )

        #expect(translated?.sentenceZhHans == "想喝杯咖啡吗？")
        #expect(translated?.contextualMeaningZhHans == nil)
    }

    @Test("例句括号内词义只取本地中文释义")
    func exampleAnnotationUsesLocalChineseMeaning() {
        let example = DictUsageExample(
            partOfSpeechLabel: "形容词",
            partOfSpeechAbbreviation: "adj.",
            meaningZh: "合适的",
            text: "Fancy a proper pint sometime this week?"
        )
        #expect(example.annotation == "（adj. 合适的）")
    }

    @Test("相同例句的并发翻译合并为一次请求并复用缓存")
    func exampleTranslationCacheDeduplicatesRequests() async {
        let cache = DictExampleTranslationCache()
        let counter = TranslationInvocationCounter()
        let actions = DictExampleTranslationActions { request in
            await counter.increment()
            try? await Task.sleep(for: .milliseconds(20))
            return DictExampleTranslation(sentenceZh: "译：\(request.sentence)")
        }
        let request = DictExampleTranslationRequest(sentence: "How are you?")

        async let first = cache.translation(for: request, using: actions)
        async let second = cache.translation(for: request, using: actions)
        let results = await (first, second)
        let cached = await cache.translation(for: request, using: actions)

        #expect(results.0?.sentenceZh == "译：How are you?")
        #expect(results.1?.sentenceZh == "译：How are you?")
        #expect(cached?.sentenceZh == "译：How are you?")
        #expect(await counter.count() == 1)
    }

    @Test("不同 WordNet sense 不共享例句翻译缓存")
    func exampleTranslationCacheSeparatesSenses() async {
        let cache = DictExampleTranslationCache()
        let counter = TranslationInvocationCounter()
        let actions = DictExampleTranslationActions { request in
            await counter.increment()
            return DictExampleTranslation(
                sentenceZhHans: "译：\(request.sentence)",
                contextualMeaningZhHans: request.stableSenseId
            )
        }
        let first = DictExampleTranslationRequest(
            sentence: "They mate in spring.",
            lemma: "mate",
            partOfSpeech: "n",
            candidateMeaningsZhHans: ["配偶", "对手"],
            stableSenseId: "mate-n-1"
        )
        let second = DictExampleTranslationRequest(
            sentence: first.sentence,
            lemma: first.lemma,
            partOfSpeech: first.partOfSpeech,
            candidateMeaningsZhHans: first.candidateMeaningsZhHans,
            stableSenseId: "mate-n-2"
        )

        async let firstResult = cache.translation(for: first, using: actions)
        async let secondResult = cache.translation(for: second, using: actions)
        let results = await (firstResult, secondResult)
        #expect(results.0?.contextualMeaningZhHans == "mate-n-1")
        #expect(results.1?.contextualMeaningZhHans == "mate-n-2")
        #expect(await counter.count() == 2)
    }

    @Test("例句只取词典固定内容并保留稳定词义身份")
    func usageExamplesUseOnlyDictionarySenses() {
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
            for: entry
        )

        #expect(groups.map(\.partOfSpeechLabel) == ["名词", "动词"])
        #expect(groups[0].examples.map(\.text) == ["The test starts at nine."])
        #expect(groups[0].examples.first?.annotation == "（n. 测试）")
        #expect(groups[1].examples.map(\.text) == ["They test the alarm every week."])
        #expect(groups[1].examples.allSatisfy { $0.annotation == "（v. 检验）" })
        let examples = groups.flatMap(\.examples)
        #expect(examples.allSatisfy { $0.translationRequest.stableSenseId != nil })
        #expect(Set(examples.map { $0.translationRequest.sentence }) == Set(entry.senses.flatMap(\.examples)))
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
            for: entry
        )
        let verbGroup = groups.first { $0.partOfSpeechLabel == "动词" }

        #expect(verbGroup?.examples.first?.annotation == "（v.）")
        #expect(verbGroup?.examples.first?.candidateMeaningsZhHans == ["把...装管", "使通过管子"])
        #expect(verbGroup?.examples.contains { $0.annotation == "（v. 管）" } == false)
        #expect(DictPartOfSpeechDisplay.labelsAreCompatible("动词", "及物动词"))
        #expect(DictPartOfSpeechDisplay.labelsAreCompatible("动词", "不及物动词"))
        #expect(!DictPartOfSpeechDisplay.labelsAreCompatible("动词", "名词"))
    }

    @Test("同一词性存在多个义项时例句括号仍使用顶部中文释义")
    func examplesKeepLocalMeaningForEverySense() async throws {
        let db = try openDatabase()
        let entry = try #require(await db.lookup("tube"))

        let groups = DictUsageExamplePolicy.groups(
            for: entry
        )
        let verbExamples = try #require(
            groups.first { $0.partOfSpeechLabel == "动词" }?.examples
        )
        #expect(verbExamples.allSatisfy { $0.annotation == "（v.）" })
        #expect(verbExamples.allSatisfy { $0.senseID != nil })
        #expect(verbExamples.allSatisfy { !$0.definitionEn!.isEmpty })
        #expect(verbExamples.first?.translationRequest.stableSenseId == verbExamples.first?.senseID)
        #expect(verbExamples.first?.translationRequest.candidateMeaningsZhHans.isEmpty == false)
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
            for: entry
        )

        #expect(groups.count == 1)
        #expect(groups[0].examples.count == 2)
        #expect(groups[0].examples.map(\.text) == [
            "An overwhelming need for solitude.",
            "They won an overwhelming majority.",
        ])
        #expect(groups[0].examples.map(\.annotation) == ["（adj.）", "（adj.）"])
    }

    @Test("原句候选返回固定搭配但不覆盖单词主释义")
    func phraseCandidatesAreSuggestions() async throws {
        let db = try openDatabase()
        let word = await db.lookup("good")
        let phrases = await db.matchingPhrases(
            ["be good at", "good at"],
            excluding: "good"
        )
        #expect(word?.word.lowercased() == "good")
        #expect(phrases.count == 1)
        #expect(phrases[0].word.lowercased() == "be good at")
    }

    @Test("相关短语只保留教材型固定搭配并限制数量")
    func relatedPhrasesPreferPedagogicalPatterns() async throws {
        let db = try openDatabase()
        let phrases = await db.relatedPhrases(for: "argue", limit: 24)

        #expect(phrases.map(\.word).contains("argue sb into doing sth"))
        #expect(!phrases.map(\.word).contains("argue with"))
        #expect(!phrases.map(\.word).contains("argue with sb"))
        #expect(!phrases.map(\.word).contains("argue about"))
        #expect(!phrases.map(\.word).contains("argue for"))
        #expect(phrases.allSatisfy { $0.word.lowercased().hasPrefix("argue ") })
        #expect(phrases.count <= 4)
    }

    @Test("介词和指示词不能反向吸附相邻词或整句")
    func functionWordsDoNotOwnPhrases() async throws {
        let db = try openDatabase()

        #expect(await db.relatedPhrases(for: "with").isEmpty)
        #expect(await db.relatedPhrases(for: "that").isEmpty)
        #expect(
            await db.matchingPhrases(
                ["argue with", "with that"],
                excluding: "with"
            ).isEmpty
        )
        #expect(
            await db.matchingPhrases(
                ["with that", "that is to say"],
                excluding: "that"
            ).isEmpty
        )
    }

    @Test("带 sb 或 somebody 的同骨架短语只保留更完整的一条")
    func equivalentPhrasePatternsAreDeduplicated() {
        let entries = [
            DictEntry(word: "argue with", translation: "和…辩论"),
            DictEntry(word: "argue with sb", translation: "跟某人辩论"),
            DictEntry(word: "argue with somebody", translation: "跟某人辩论"),
        ]

        let phrases = DictPhraseDisplayPolicy.deduplicated(entries)
        #expect(phrases.count == 1)
        #expect(phrases[0].word == "argue with sb")
    }

    @Test("普通复合名词不冒充固定短语")
    func plainCompoundNounsAreNotPhrases() async throws {
        let db = try openDatabase()

        #expect(await db.relatedPhrases(for: "coffee").isEmpty)
        #expect(
            await db.matchingPhrases(
                ["coffee shop", "coffee bean", "coffee break"],
                excluding: "coffee"
            ).isEmpty
        )
    }

    @Test("学校常教的介词搭配仍会展示")
    func schoolTaughtPatternsRemainVisible() async throws {
        let db = try openDatabase()
        let phrases = await db.relatedPhrases(for: "good")

        #expect(phrases.map(\.word).contains("good at"))
        #expect(phrases.map(\.word).contains("good for"))
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

    @Test("领域标签不再被误当词性")
    func domainLabelIsSeparatedFromPartOfSpeech() async throws {
        let db = try openDatabase()
        let raining = try #require(await db.lookup("raining"))
        let meaning = try #require(raining.meaningGroups.first)

        #expect(meaning.partOfSpeech == "现在分词")
        #expect(meaning.meaning == "【化学】淋降现象")
        #expect(meaning.partOfSpeechAbbreviation == "v.")
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

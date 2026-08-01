import DictKit
import Foundation
import Testing
@testable import DomainKit

@Suite("KeywordAnnotator")
struct KeywordAnnotatorTests {
    private func makeAnnotator() throws -> KeywordAnnotator {
        let url = try #require(Bundle.main.url(forResource: "learner_dictionary", withExtension: "sqlite"))
        return KeywordAnnotator(dictionary: try DictDatabase(databaseURL: url))
    }

    @Test("生僻词被标注、常见词不标注（小学阈值）")
    func rareWordsUnderlined() async throws {
        let annotator = try makeAnnotator()
        let words = await annotator.keywords(
            in: "The tousled magpie is a nuisance, but I like it.",
            frequencyThreshold: 3000
        )
        // magpie/nuisance 属低频词
        #expect(words.contains("nuisance") || words.contains("magpie"))
        // like/the/but 高频，不标注
        #expect(!words.contains("like"))
        #expect(!words.contains("the"))
    }

    @Test("高阈值（研究生）时常规词汇不再标注")
    func highThresholdFewerKeywords() async throws {
        let annotator = try makeAnnotator()
        let text = "I usually prefer reading interesting novels during holidays."
        let lowLevel = await annotator.keywords(in: text, frequencyThreshold: 3000)
        let highLevel = await annotator.keywords(in: text, frequencyThreshold: 25000)
        #expect(highLevel.count <= lowLevel.count)
    }

    @Test("停用词永不标注")
    func stopwordsExcluded() async throws {
        let annotator = try makeAnnotator()
        let words = await annotator.keywords(
            in: "something anything everything between because",
            frequencyThreshold: 100 // 极低阈值，所有词都"生僻"
        )
        #expect(words.isEmpty)
    }

    @Test("keywordRangesJSON 编解码往返")
    func payloadRoundTrip() {
        let json = KeywordAnnotator.encode(words: ["magpie", "nuisance"])
        #expect(json != nil)
        let decoded = KeywordAnnotator.decodeWords(fromJSON: json)
        #expect(decoded == ["magpie", "nuisance"])
        #expect(KeywordAnnotator.decodeWords(fromJSON: nil).isEmpty)
        #expect(KeywordAnnotator.encode(words: []) == nil)
    }

    @Test("isRare：frq/bnc 取小、双 0 视为生僻")
    func rareJudgement() {
        func entry(frq: Int, bnc: Int) -> DictEntry {
            DictEntry(word: "x", bnc: bnc, frq: frq)
        }
        #expect(KeywordAnnotator.isRare(entry: entry(frq: 0, bnc: 0), threshold: 3000))
        #expect(!KeywordAnnotator.isRare(entry: entry(frq: 500, bnc: 0), threshold: 3000))
        #expect(KeywordAnnotator.isRare(entry: entry(frq: 9000, bnc: 0), threshold: 3000))
        #expect(!KeywordAnnotator.isRare(entry: entry(frq: 9000, bnc: 2000), threshold: 3000))
    }
}

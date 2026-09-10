@testable import DictKit
import Testing

struct GrammarTermCatalogTests {
    @Test("专业术语最长优先匹配")
    func longestTermWins() {
        let segments = GrammarTermCatalog.segments(in: "缺少主语和系动词，不能只补动词。")
        let matches = segments.compactMap { segment -> String? in
            guard case .term(let term) = segment else { return nil }
            return term
        }

        #expect(matches == ["主语", "系动词", "动词"])
        #expect(segments.contains(.term("系动词")))
    }

    @Test("随包术语均包含可直接学习的完整内容")
    func everyEntryIsComplete() {
        #expect(GrammarTermCatalog.entries.count >= 25)
        for entry in GrammarTermCatalog.entries {
            #expect(!entry.term.isEmpty)
            #expect(!entry.definition.isEmpty, "\(entry.term) 缺少定义")
            #expect(!entry.usage.isEmpty, "\(entry.term) 缺少用法")
            #expect(!entry.commonForms.isEmpty, "\(entry.term) 缺少常见形式")
            #expect(!entry.examples.isEmpty, "\(entry.term) 缺少例句")
            for example in entry.examples {
                #expect(!example.english.isEmpty)
                #expect(!example.chinese.isEmpty)
                #expect(!example.highlights.isEmpty)
                #expect(example.highlights.allSatisfy(example.english.contains))
            }
        }
    }

    @Test("系动词卡包含定义、常见词和高亮例句")
    func linkingVerbReference() throws {
        let entry = try #require(GrammarTermCatalog.entry(for: "系动词"))
        #expect(entry.definition.contains("主语"))
        #expect(entry.definition.contains("表语"))
        #expect(entry.commonForms.joined().contains("be"))
        #expect(entry.commonForms.joined().contains("seem"))
        #expect(entry.commonForms.joined().contains("smell"))
        let example = try #require(entry.examples.first)
        #expect(example.english == "The coffee smells wonderful.")
        #expect(example.highlights == ["smells"])
    }
}

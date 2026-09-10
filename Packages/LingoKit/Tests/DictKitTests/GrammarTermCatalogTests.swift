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

    @Test("常见语法类别及主语卡的关联术语均可查阅")
    func commonGrammarCoverage() throws {
        let expected = [
            "名词短语", "动词短语", "介词短语", "可数名词", "不可数名词", "专有名词",
            "人称代词", "物主代词", "反身代词", "关系代词", "关系副词", "先行词",
            "直接宾语", "间接宾语", "介词宾语", "主语补语", "宾语补语",
            "主谓一致", "非谓语动词", "比较级", "最高级", "限定词", "数词",
            "一般现在时", "一般过去时", "一般将来时", "过去将来时",
            "现在进行时", "过去进行时", "现在完成时", "过去完成时", "现在完成进行时",
            "名词性从句", "主语从句", "表语从句", "同位语从句", "条件状语从句",
            "限制性定语从句", "非限制性定语从句", "主动语态", "虚拟语气",
            "祈使句", "感叹句", "倒装句", "强调句", "反意疑问句", "间接引语",
        ]
        for term in expected {
            #expect(GrammarTermCatalog.entry(for: term) != nil, "缺少常见术语：\(term)")
        }
        let subject = try #require(GrammarTermCatalog.entry(for: "主语"))
        for form in subject.commonForms {
            #expect(GrammarTermCatalog.entry(for: form) != nil, "关联术语无法打开：\(form)")
        }
        #expect(Set(GrammarTermCatalog.entries.map(\.term)).count == GrammarTermCatalog.entries.count)
    }

    @Test("长术语链接不会误跳到内含的短术语，正文保持完整")
    func nestedTermsAndRoundTrip() {
        let text = "非限制性定语从句、现在完成进行时，以及间接宾语与宾语补语。"
        let segments = GrammarTermCatalog.segments(in: text)
        let terms = segments.compactMap { segment -> String? in
            if case .term(let term) = segment { return term }
            return nil
        }
        #expect(terms == ["非限制性定语从句", "现在完成进行时", "间接宾语", "宾语补语"])
        let rebuilt = segments.map { segment in
            switch segment {
            case .term(let value), .text(let value): value
            }
        }.joined()
        #expect(rebuilt == text)
        #expect(GrammarTermCatalog.entry(for: "  名词短语\n")?.term == "名词短语")
        #expect(GrammarTermCatalog.entry(for: "不存在的术语") == nil)
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

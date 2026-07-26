import CoreKit
import Foundation
import Testing
@testable import DictKit

@Suite("GrammarPointStore")
struct GrammarPointStoreTests {
    private func openStore() throws -> GrammarPointStore {
        let url = try #require(Bundle.main.url(forResource: "grammar_points", withExtension: "json"))
        return try GrammarPointStore(url: url)
    }

    @Test("内置语法点库可解码且数量达标（首批 30+）")
    func decodeBundledFile() throws {
        let store = try openStore()
        #expect(store.allPoints.count >= 30)
    }

    @Test("trigger 命中：单击 as 能看到 as...as 用法")
    func triggerLookup() throws {
        let store = try openStore()
        let points = store.points(forTrigger: "as")
        #expect(points.contains { $0.id == "as-as" })
        // 大小写不敏感
        #expect(!store.points(forTrigger: "As").isEmpty)
    }

    @Test("related 引用全部可解析（无悬空跳转）")
    func relatedIntegrity() throws {
        let store = try openStore()
        for point in store.allPoints {
            for relatedID in point.related {
                #expect(store.point(id: relatedID) != nil, "悬空 related: \(point.id) → \(relatedID)")
            }
        }
    }

    @Test("每个语法点都有中文讲解与至少一个例句")
    func contentCompleteness() throws {
        let store = try openStore()
        for point in store.allPoints {
            #expect(!point.explanationZh.isEmpty, "\(point.id)")
            #expect(!point.examples.isEmpty, "\(point.id)")
        }
    }

    @Test("全部语法点都配置了合法的对话检测模式")
    func grammarPatternsAreComplete() throws {
        let store = try openStore()
        for point in store.allPoints {
            let patterns = try #require(point.patterns, "\(point.id) 缺少 patterns")
            #expect(!patterns.isEmpty, "\(point.id)")
            for pattern in patterns {
                #expect(!pattern.steps.isEmpty, "\(point.id)")
                #expect(
                    pattern.maximumGaps.count == max(0, pattern.steps.count - 1),
                    "\(point.id) 的 maximumGaps 数量错误"
                )
                if let highlightedSteps = pattern.highlightedSteps {
                    #expect(
                        highlightedSteps.allSatisfy(pattern.steps.indices.contains),
                        "\(point.id) 的 highlightedSteps 越界"
                    )
                }
            }
        }
    }

    @Test("完整命中 not only...but also 并高亮四个结构词")
    func detectsNotOnlyButAlso() throws {
        let store = try openStore()
        let tokens = WordTokenizer.tokenize(
            "She's not only thoughtful but also genuinely funny."
        )
        let match = try #require(
            store.matches(in: tokens).first { $0.pointID == "not-only-but-also" }
        )

        #expect(words(for: match, in: tokens) == ["not", "only", "but", "also"])
    }

    @Test("成对命中 as...as，不完整结构不误报")
    func detectsCompleteAsAsOnly() throws {
        let store = try openStore()
        let complete = WordTokenizer.tokenize("This café is as cozy as my room.")
        let match = try #require(
            store.matches(in: complete).first { $0.pointID == "as-as" }
        )
        #expect(words(for: match, in: complete) == ["as", "as"])

        let incomplete = WordTokenizer.tokenize("This café is as cozy.")
        #expect(!store.matches(in: incomplete).contains { $0.pointID == "as-as" })
    }

    @Test("语法模式不会跨越句号错误配对")
    func doesNotCrossSentenceBoundary() throws {
        let store = try openStore()
        let tokens = WordTokenizer.tokenize("It was so nice. That made my day.")

        #expect(!store.matches(in: tokens).contains { $0.pointID == "so-that-result" })
    }

    @Test("更具体的 so that 目的结构优先于结果结构")
    func prefersSpecificPurposePattern() throws {
        let store = try openStore()
        let tokens = WordTokenizer.tokenize("Speak clearly so that everyone can hear you.")
        let annotations = store.annotations(in: tokens)
        let pointIDs = Set(annotations.values)

        #expect(pointIDs.contains("so-that-purpose"))
        #expect(!pointIDs.contains("so-that-result"))
        #expect(
            annotations.compactMap { tokenID, pointID in
                pointID == "so-that-purpose" ? tokens[tokenID].word : nil
            }.sorted() == ["so", "that"]
        )
    }

    private func words(for match: GrammarMatch, in tokens: [TextToken]) -> [String] {
        match.tokenIDs.compactMap { tokens[$0].word }
    }
}

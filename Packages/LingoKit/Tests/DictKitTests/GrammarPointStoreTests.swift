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
}

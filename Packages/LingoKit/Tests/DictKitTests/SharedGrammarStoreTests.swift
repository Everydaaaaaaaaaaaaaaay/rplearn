import Foundation
import CoreKit
import Testing
@testable import DictKit

@Suite("Shared grammar local persistence")
struct SharedGrammarStoreTests {
    @Test("下载规则持久保存、重新打开可离线命中，同ID和同结构不同描述不重复")
    func persistentMergeAndDeduplication() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = directory.appendingPathComponent("grammar.json")
        let point = GrammarPoint(id: "shared-0123456789abcdef0123456789abcdef", triggers: ["do"], title: "do强调", explanationZh: "do 加动词原形可以强调动作。",
            examples: [.init(en: "I do like it.", zh: "我确实喜欢它。")], related: [],
            patterns: [.init(steps: ["do", "<word>"], maximumGaps: [0])])
        let store = GrammarPointStore(points: [], sharedCacheURL: cache)
        store.mergeSharedPoints([point, point])
        var synonym = point; synonym.id = "shared-abcdef0123456789abcdef0123456789"; synonym.title = "强调肯定动词"
        store.mergeSharedPoints([synonym])
        #expect(store.allPoints.count == 1)
        let reopened = GrammarPointStore(points: [], sharedCacheURL: cache)
        #expect(reopened.point(id: point.id)?.title == "do强调")
        #expect(!reopened.matches(in: WordTokenizer.tokenize("I do like it.")).isEmpty)
        var unsafe = point; unsafe.id = "shared-11111111111111111111111111111111"
        unsafe.patterns = [.init(steps: ["<word>", "<word>"], maximumGaps: [400])]
        reopened.mergeSharedPoints([unsafe])
        #expect(reopened.allPoints.count == 1)
    }
}

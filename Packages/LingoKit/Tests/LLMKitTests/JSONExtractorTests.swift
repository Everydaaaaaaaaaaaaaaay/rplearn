import Foundation
import Testing
@testable import LLMKit

@Suite("JSONExtractor")
struct JSONExtractorTests {
    private struct Payload: Decodable, Equatable {
        let name: String
    }

    @Test("直接解析纯 JSON")
    func plainJSON() throws {
        let result = try JSONExtractor.decode(Payload.self, from: #"{"name":"a"}"#)
        #expect(result == Payload(name: "a"))
    }

    @Test("剥去 Markdown 代码围栏")
    func fencedJSON() throws {
        let text = """
        ```json
        {"name":"b"}
        ```
        """
        let result = try JSONExtractor.decode(Payload.self, from: text)
        #expect(result == Payload(name: "b"))
    }

    @Test("从解释性文本中截取花括号片段")
    func embeddedJSON() throws {
        let text = #"好的，以下是结果：{"name":"c"}，希望有帮助。"#
        let result = try JSONExtractor.decode(Payload.self, from: text)
        #expect(result == Payload(name: "c"))
    }

    @Test("完全无 JSON 时抛错")
    func noJSON() {
        #expect(throws: LLMError.self) {
            try JSONExtractor.decode(Payload.self, from: "这里没有任何结构化内容")
        }
    }
}

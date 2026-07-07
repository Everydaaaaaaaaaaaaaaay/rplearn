import Testing
@testable import LLMKit

@Suite("SSEParser")
struct SSEParserTests {
    @Test("event + data 行组成一个事件")
    func eventAndData() {
        var parser = SSEParser()
        #expect(parser.feed(line: "event: content_block_delta") == nil)
        let event = parser.feed(line: #"data: {"type":"content_block_delta"}"#)
        #expect(event == SSEParser.Event(name: "content_block_delta", data: #"{"type":"content_block_delta"}"#))
    }

    @Test("无 event 名的裸 data 行（OpenAI 风格）")
    func bareDataLine() {
        var parser = SSEParser()
        let event = parser.feed(line: "data: [DONE]")
        #expect(event == SSEParser.Event(name: nil, data: "[DONE]"))
    }

    @Test("注释与未知字段被忽略")
    func commentsIgnored() {
        var parser = SSEParser()
        #expect(parser.feed(line: ": keep-alive") == nil)
        #expect(parser.feed(line: "id: 42") == nil)
        #expect(parser.feed(line: "retry: 1000") == nil)
        #expect(parser.feed(line: "") == nil)
    }

    @Test("事件名沿用到下一个 event 行出现")
    func eventNameCarriesOver() {
        var parser = SSEParser()
        _ = parser.feed(line: "event: a")
        #expect(parser.feed(line: "data: 1")?.name == "a")
        _ = parser.feed(line: "event: b")
        #expect(parser.feed(line: "data: 2")?.name == "b")
    }

    @Test("data 值保留冒号后除首空格外的内容")
    func dataValueTrimming() {
        var parser = SSEParser()
        #expect(parser.feed(line: "data:  spaced")?.data == " spaced")
        #expect(parser.feed(line: "data:tight")?.data == "tight")
    }
}

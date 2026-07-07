import Foundation
import Testing
@testable import LLMKit

@Suite("OpenAIProvider 解析")
struct OpenAIProviderTests {
    private let config = LLMProviderConfig(
        kind: .openai,
        apiKey: "test-key",
        baseURL: URL(string: "https://api.openai.com")!,
        models: [:]
    )

    @Test("SSE fixture 流还原完整文本并以 [DONE] 结束")
    func streamFixture() {
        let lines = [
            #"data: {"choices":[{"delta":{"role":"assistant","content":""}}]}"#,
            #"data: {"choices":[{"delta":{"content":"Hel"}}]}"#,
            #"data: {"choices":[{"delta":{"content":"lo"}}]}"#,
            #"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#,
            "data: [DONE]",
        ]
        var parser = SSEParser()
        var text = ""
        for line in lines {
            guard let event = parser.feed(line: line) else { continue }
            if event.data == "[DONE]" { break }
            if let delta = OpenAIProvider.decodeStreamDelta(event) {
                text += delta
            }
        }
        #expect(text == "Hello")
    }

    @Test("非流式响应取 choices[0].message.content")
    func completionParsing() throws {
        let json = #"{"choices":[{"message":{"role":"assistant","content":"Hi"}}]}"#
        let text = try OpenAIProvider.extractText(fromResponseData: Data(json.utf8))
        #expect(text == "Hi")
    }

    @Test("baseURL 已含 /v1 时不重复拼接")
    func urlJoining() {
        let withV1 = OpenAIProvider.chatCompletionsURL(baseURL: URL(string: "https://example.com/v1")!)
        #expect(withV1.absoluteString == "https://example.com/v1/chat/completions")
        let withoutV1 = OpenAIProvider.chatCompletionsURL(baseURL: URL(string: "https://api.openai.com")!)
        #expect(withoutV1.absoluteString == "https://api.openai.com/v1/chat/completions")
    }

    @Test("json_schema 降级为 prompt 内嵌 schema")
    func schemaDegradation() {
        let request = LLMRequest(
            tier: .fast,
            system: "原始 system",
            messages: [.user("hi")],
            responseFormat: .jsonSchema(name: "x", schema: ["type": "object"])
        )
        let degraded = OpenAIProvider.degradedToInlineSchema(request)
        #expect(degraded.responseFormat == .text)
        #expect(degraded.system?.contains("原始 system") == true)
        #expect(degraded.system?.contains("JSON Schema") == true)
    }

    @Test("请求体：system 作为首条消息、response_format 结构")
    func bodyBuilding() {
        let provider = OpenAIProvider(config: config)
        let request = LLMRequest(
            tier: .balanced,
            system: "sys",
            messages: [.user("hi")],
            temperature: 0.9,
            responseFormat: .jsonSchema(name: "card", schema: ["type": "object"])
        )
        let body = provider.makeBody(request, stream: false)
        let messages = body["messages"] as? [[String: Any]]
        #expect(messages?.first?["role"] as? String == "system")
        #expect(messages?.count == 2)
        #expect(body["temperature"] as? Double == 0.9)
        let responseFormat = body["response_format"] as? [String: Any]
        #expect(responseFormat?["type"] as? String == "json_schema")
    }
}

import Foundation
import Testing
@testable import LLMKit

@Suite("AnthropicProvider 解析")
struct AnthropicProviderTests {
    private let config = LLMProviderConfig(
        kind: .anthropic,
        apiKey: "test-key",
        baseURL: URL(string: "https://api.anthropic.com")!,
        models: [:]
    )

    @Test("SSE fixture 流还原完整文本")
    func streamFixture() throws {
        let lines = [
            "event: message_start",
            #"data: {"type":"message_start","message":{"id":"msg_1"}}"#,
            "event: content_block_start",
            #"data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
            "event: content_block_delta",
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hel"}}"#,
            "event: content_block_delta",
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"lo"}}"#,
            "event: content_block_stop",
            #"data: {"type":"content_block_stop","index":0}"#,
            "event: message_delta",
            #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":2}}"#,
            "event: message_stop",
            #"data: {"type":"message_stop"}"#,
        ]
        var parser = SSEParser()
        var text = ""
        for line in lines {
            guard let event = parser.feed(line: line) else { continue }
            if let delta = try AnthropicProvider.decodeStreamDelta(event) {
                text += delta
            }
        }
        #expect(text == "Hello")
    }

    @Test("流中 error 事件抛出可重试错误")
    func streamError() {
        let event = SSEParser.Event(
            name: "error",
            data: #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#
        )
        #expect(throws: LLMError.http(status: 529, message: "Overloaded")) {
            try AnthropicProvider.decodeStreamDelta(event)
        }
    }

    @Test("非流式响应取全部 text 块")
    func completionParsing() throws {
        let json = #"{"content":[{"type":"text","text":"Hi "},{"type":"text","text":"there"}],"stop_reason":"end_turn"}"#
        let text = try AnthropicProvider.extractText(fromResponseData: Data(json.utf8))
        #expect(text == "Hi there")
    }

    @Test("refusal 停止原因抛错")
    func refusalThrows() {
        let json = #"{"content":[],"stop_reason":"refusal"}"#
        #expect(throws: LLMError.self) {
            try AnthropicProvider.extractText(fromResponseData: Data(json.utf8))
        }
    }

    @Test("请求体：system 顶层、消息、结构化输出")
    func bodyBuilding() throws {
        let provider = AnthropicProvider(config: config)
        let request = LLMRequest(
            task: .conversation,
            tier: .fast,
            system: "You are a coach.",
            messages: [.user("hi")],
            maxTokens: 100,
            temperature: 0.2,
            responseFormat: .jsonSchema(name: "review", schema: ["type": "object"])
        )
        let body = provider.makeBody(request, stream: false)
        #expect(body["model"] as? String == "claude-haiku-4-5")
        #expect(body["system"] as? String == "You are a coach.")
        #expect(body["temperature"] as? Double == 0.2)
        let outputConfig = body["output_config"] as? [String: Any]
        let format = outputConfig?["format"] as? [String: Any]
        #expect(format?["type"] as? String == "json_schema")
    }

    @Test("不支持采样参数的模型自动丢弃 temperature")
    func samplingDroppedForNewModels() {
        #expect(!AnthropicProvider.supportsSamplingParameters(modelID: "claude-sonnet-5"))
        #expect(!AnthropicProvider.supportsSamplingParameters(modelID: "claude-opus-4-8"))
        #expect(AnthropicProvider.supportsSamplingParameters(modelID: "claude-haiku-4-5"))

        let provider = AnthropicProvider(config: config)
        let request = LLMRequest(
            task: .conversation,
            tier: .balanced,
            messages: [.user("hi")],
            temperature: 0.9
        )
        let body = provider.makeBody(request, stream: true)
        #expect(body["temperature"] == nil)
        #expect(body["stream"] as? Bool == true)
    }
}

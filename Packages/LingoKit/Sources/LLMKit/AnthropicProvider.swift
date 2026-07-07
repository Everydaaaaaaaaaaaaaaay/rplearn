import Foundation

/// Anthropic Messages API（POST /v1/messages）。
/// SSE 事件：message_start / content_block_delta(text_delta) / message_delta / message_stop。
public struct AnthropicProvider: LLMProvider {
    private let config: LLMProviderConfig
    private let session: URLSession

    public init(config: LLMProviderConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    public func modelID(for tier: LLMTier) -> String {
        config.modelID(for: tier)
    }

    public func complete(_ request: LLMRequest) async throws -> String {
        let urlRequest = try makeURLRequest(request, stream: false)
        let (data, response) = try await session.data(for: urlRequest)
        try Self.validate(response: response, data: data)
        return try Self.extractText(fromResponseData: data)
    }

    public func stream(_ request: LLMRequest) async -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let urlRequest = try makeURLRequest(request, stream: true)
                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                        var body = ""
                        for try await line in bytes.lines {
                            body += line
                            if body.count > 4096 { break }
                        }
                        throw LLMError.http(status: http.statusCode, message: Self.apiErrorMessage(in: Data(body.utf8)) ?? body)
                    }
                    var parser = SSEParser()
                    for try await line in bytes.lines {
                        guard let event = parser.feed(line: line) else { continue }
                        if let delta = try Self.decodeStreamDelta(event) {
                            continuation.yield(.textDelta(delta))
                        }
                        if event.name == "message_stop" { break }
                    }
                    continuation.yield(.finished)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - 请求构建

    private func makeURLRequest(_ request: LLMRequest, stream: Bool) throws -> URLRequest {
        guard !config.apiKey.isEmpty else { throw LLMError.missingAPIKey }
        let url = config.baseURL.appendingPathComponent("v1/messages")
        var urlRequest = URLRequest(url: url, timeoutInterval: 120)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: makeBody(request, stream: stream))
        return urlRequest
    }

    func makeBody(_ request: LLMRequest, stream: Bool) -> [String: Any] {
        var body: [String: Any] = [
            "model": modelID(for: request.tier),
            "max_tokens": request.maxTokens,
            "messages": request.messages.map { ["role": $0.role.rawValue, "content": $0.content] },
        ]
        if let system = request.system, !system.isEmpty {
            body["system"] = system
        }
        // claude-sonnet-5 / claude-opus-4-7+ / claude-fable-5 已移除采样参数，传入会直接 400。
        if let temperature = request.temperature,
           Self.supportsSamplingParameters(modelID: modelID(for: request.tier)) {
            body["temperature"] = temperature
        }
        if case .jsonSchema(_, let schema) = request.responseFormat {
            body["output_config"] = [
                "format": [
                    "type": "json_schema",
                    "schema": schema.foundationObject,
                ],
            ]
        }
        if stream {
            body["stream"] = true
        }
        return body
    }

    static func supportsSamplingParameters(modelID: String) -> Bool {
        let unsupportedMarkers = ["sonnet-5", "opus-4-7", "opus-4-8", "fable", "mythos"]
        return !unsupportedMarkers.contains { modelID.contains($0) }
    }

    // MARK: - 响应解析（纯函数，便于 fixture 单测）

    private struct CompletionResponse: Decodable {
        struct ContentBlock: Decodable {
            let type: String
            let text: String?
        }
        let content: [ContentBlock]
        let stopReason: String?

        enum CodingKeys: String, CodingKey {
            case content
            case stopReason = "stop_reason"
        }
    }

    static func extractText(fromResponseData data: Data) throws -> String {
        let response: CompletionResponse
        do {
            response = try JSONDecoder().decode(CompletionResponse.self, from: data)
        } catch {
            throw LLMError.invalidResponse("Anthropic 响应解码失败：\(error.localizedDescription)")
        }
        if response.stopReason == "refusal" {
            throw LLMError.refused("safety refusal")
        }
        let text = response.content.compactMap { $0.type == "text" ? $0.text : nil }.joined()
        guard !text.isEmpty else { throw LLMError.emptyResponse }
        return text
    }

    private struct StreamPayload: Decodable {
        struct Delta: Decodable {
            let type: String?
            let text: String?
            let stopReason: String?

            enum CodingKeys: String, CodingKey {
                case type, text
                case stopReason = "stop_reason"
            }
        }
        struct APIError: Decodable {
            let type: String?
            let message: String?
        }
        let type: String
        let delta: Delta?
        let error: APIError?
    }

    /// 解析一条 SSE 事件；返回文本增量（若有）。遇到 error 事件或 refusal 抛错。
    static func decodeStreamDelta(_ event: SSEParser.Event) throws -> String? {
        guard let payload = try? JSONDecoder().decode(StreamPayload.self, from: Data(event.data.utf8)) else {
            return nil // 未知事件宽容忽略
        }
        switch payload.type {
        case "content_block_delta":
            guard payload.delta?.type == "text_delta" else { return nil }
            return payload.delta?.text
        case "message_delta":
            if payload.delta?.stopReason == "refusal" {
                throw LLMError.refused("safety refusal")
            }
            return nil
        case "error":
            // 流中错误（如 overloaded_error）按 5xx 处理，允许 Router 在未收到增量时重试。
            throw LLMError.http(status: 529, message: payload.error?.message ?? "stream error")
        default:
            return nil
        }
    }

    static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard http.statusCode >= 400 else { return }
        throw LLMError.http(
            status: http.statusCode,
            message: apiErrorMessage(in: data) ?? String(decoding: data.prefix(512), as: UTF8.self)
        )
    }

    static func apiErrorMessage(in data: Data) -> String? {
        struct ErrorEnvelope: Decodable {
            struct APIError: Decodable { let message: String? }
            let error: APIError?
        }
        return (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.error?.message
    }
}

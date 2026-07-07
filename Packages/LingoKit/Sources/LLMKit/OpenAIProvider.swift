import Foundation

/// OpenAI Chat Completions API（POST /v1/chat/completions）。
/// 也承载「自定义 OpenAI 兼容端点」：可配 baseURL；json_schema 被 400 拒绝时降级为 prompt 内嵌 schema。
public struct OpenAIProvider: LLMProvider {
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
        do {
            return try await completeOnce(request)
        } catch let error as LLMError {
            // 兼容端点可能不支持 response_format: json_schema —— 降级为 prompt 内嵌 schema 再试一次。
            if case .http(let status, _) = error, status == 400, requestUsesJSONSchema(request) {
                return try await completeOnce(Self.degradedToInlineSchema(request))
            }
            throw error
        }
    }

    private func completeOnce(_ request: LLMRequest) async throws -> String {
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
                        if event.data == "[DONE]" { break }
                        if let delta = Self.decodeStreamDelta(event) {
                            continuation.yield(.textDelta(delta))
                        }
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

    private func requestUsesJSONSchema(_ request: LLMRequest) -> Bool {
        if case .jsonSchema = request.responseFormat { return true }
        return false
    }

    /// json_schema 降级：改为普通文本输出，把 schema 塞进 system 提示。
    static func degradedToInlineSchema(_ request: LLMRequest) -> LLMRequest {
        guard case .jsonSchema(_, let schema) = request.responseFormat else { return request }
        var degraded = request
        degraded.responseFormat = .text
        let schemaText: String
        if let data = try? JSONEncoder().encode(schema), let text = String(data: data, encoding: .utf8) {
            schemaText = text
        } else {
            schemaText = "{}"
        }
        let instruction = "你必须只输出一个符合以下 JSON Schema 的 JSON 对象，不要输出任何其他内容（包括解释、Markdown 围栏）：\n\(schemaText)"
        degraded.system = [request.system, instruction].compactMap(\.self).joined(separator: "\n\n")
        return degraded
    }

    private func makeURLRequest(_ request: LLMRequest, stream: Bool) throws -> URLRequest {
        let url = Self.chatCompletionsURL(baseURL: config.baseURL)
        var urlRequest = URLRequest(url: url, timeoutInterval: 120)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !config.apiKey.isEmpty {
            urlRequest.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: makeBody(request, stream: stream))
        return urlRequest
    }

    /// baseURL 已带 /v1 时不再重复拼接（自定义端点常见写法两者皆有）。
    static func chatCompletionsURL(baseURL: URL) -> URL {
        if baseURL.path.hasSuffix("/v1") || baseURL.path.hasSuffix("/v1/") {
            return baseURL.appendingPathComponent("chat/completions")
        }
        return baseURL.appendingPathComponent("v1/chat/completions")
    }

    func makeBody(_ request: LLMRequest, stream: Bool) -> [String: Any] {
        var messages: [[String: Any]] = []
        if let system = request.system, !system.isEmpty {
            messages.append(["role": "system", "content": system])
        }
        messages.append(contentsOf: request.messages.map { ["role": $0.role.rawValue, "content": $0.content] })

        var body: [String: Any] = [
            "model": modelID(for: request.tier),
            "max_tokens": request.maxTokens,
            "messages": messages,
        ]
        if let temperature = request.temperature {
            body["temperature"] = temperature
        }
        if case .jsonSchema(let name, let schema) = request.responseFormat {
            body["response_format"] = [
                "type": "json_schema",
                "json_schema": [
                    "name": name,
                    "strict": true,
                    "schema": schema.foundationObject,
                ],
            ]
        }
        if stream {
            body["stream"] = true
        }
        return body
    }

    // MARK: - 响应解析（纯函数，便于 fixture 单测）

    private struct CompletionResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message?
        }
        let choices: [Choice]
    }

    static func extractText(fromResponseData data: Data) throws -> String {
        let response: CompletionResponse
        do {
            response = try JSONDecoder().decode(CompletionResponse.self, from: data)
        } catch {
            throw LLMError.invalidResponse("OpenAI 响应解码失败：\(error.localizedDescription)")
        }
        guard let text = response.choices.first?.message?.content, !text.isEmpty else {
            throw LLMError.emptyResponse
        }
        return text
    }

    private struct StreamChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable { let content: String? }
            let delta: Delta?
        }
        let choices: [Choice]?
    }

    static func decodeStreamDelta(_ event: SSEParser.Event) -> String? {
        guard let chunk = try? JSONDecoder().decode(StreamChunk.self, from: Data(event.data.utf8)) else {
            return nil // 未知事件宽容忽略
        }
        return chunk.choices?.first?.delta?.content
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

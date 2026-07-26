import BackendKit
import Foundation

public struct BackendLLMProvider: LLMProvider {
    private struct Message: Codable, Sendable {
        let content: String
        let role: String
    }

    private struct RequestBody: Encodable, Sendable {
        let maxOutputTokens: Int
        let messages: [Message]
        let responseFormat: String
        let task: String
    }

    private struct Completion: Decodable, Sendable {
        let content: String
    }

    private struct Delta: Decodable {
        let text: String
    }

    private struct StreamFailure: Decodable {
        let code: String
        let retryable: Bool
    }

    private let backend: BackendClient

    public init(backend: BackendClient) {
        self.backend = backend
    }

    public func modelID(for tier: LLMTier) -> String {
        "server-managed"
    }

    public func complete(_ request: LLMRequest) async throws -> String {
        do {
            let completion: Completion = try await backend.send(
                path: "/v1/ai/completions",
                method: "POST",
                body: try makeBody(request)
            )
            guard !completion.content.isEmpty else {
                throw LLMError.emptyResponse
            }
            return completion.content
        } catch {
            throw Self.map(error)
        }
    }

    public func stream(
        _ request: LLMRequest
    ) async -> AsyncThrowingStream<LLMStreamEvent, Error> {
        do {
            let events = try await backend.eventStream(
                path: "/v1/ai/stream",
                body: try makeBody(request)
            )
            return AsyncThrowingStream { continuation in
                let task = Task {
                    var receivedDone = false
                    do {
                        for try await event in events {
                            try Task.checkCancellation()
                            switch event.name {
                            case "delta":
                                let delta = try JSONDecoder().decode(
                                    Delta.self,
                                    from: Data(event.data.utf8)
                                )
                                if !delta.text.isEmpty {
                                    continuation.yield(.textDelta(delta.text))
                                }
                            case "done":
                                receivedDone = true
                                continuation.yield(.finished)
                            case "error":
                                let failure = try JSONDecoder().decode(
                                    StreamFailure.self,
                                    from: Data(event.data.utf8)
                                )
                                throw LLMError.http(
                                    status: failure.retryable ? 503 : 400,
                                    message: failure.code
                                )
                            case "metadata", "usage":
                                continue
                            default:
                                continue
                            }
                        }
                        guard receivedDone else {
                            throw LLMError.invalidResponse("AI 流在完成事件前中断")
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: Self.map(error))
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        } catch {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: Self.map(error))
            }
        }
    }

    private func makeBody(_ request: LLMRequest) throws -> RequestBody {
        var messages: [Message] = []
        var systemParts = [request.system].compactMap { $0 }
        let responseFormat: String
        switch request.responseFormat {
        case .text:
            responseFormat = "text"
        case .jsonSchema(let name, let schema):
            let schemaData = try JSONEncoder().encode(schema)
            let schemaText = String(decoding: schemaData, as: UTF8.self)
            systemParts.append(
                """
                Return only one JSON object matching schema "\(name)". Do not add Markdown or explanation.
                JSON Schema:
                \(schemaText)
                """
            )
            responseFormat = "json_object"
        }
        if !systemParts.isEmpty {
            messages.append(
                Message(
                    content: systemParts.joined(separator: "\n\n"),
                    role: "system"
                )
            )
        }
        messages.append(
            contentsOf: request.messages.map {
                Message(content: $0.content, role: $0.role.rawValue)
            }
        )
        return RequestBody(
            maxOutputTokens: request.maxTokens,
            messages: messages,
            responseFormat: responseFormat,
            task: request.task.rawValue
        )
    }

    private static func map(_ error: Error) -> Error {
        guard let backendError = error as? BackendClientError else { return error }
        switch backendError {
        case .api(_, let message, _, let status):
            return LLMError.http(status: status, message: message)
        case .invalidResponse:
            return LLMError.invalidResponse("后端 AI 响应无法解析")
        case .signedOut:
            return LLMError.http(status: 401, message: "登录后可使用云端 AI 对话")
        case .transport:
            return URLError(.networkConnectionLost)
        }
    }
}

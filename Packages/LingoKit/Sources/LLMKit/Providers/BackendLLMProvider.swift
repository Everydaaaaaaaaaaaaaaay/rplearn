import CoreKit
import BackendKit
import Foundation

public struct BackendLLMUsage: Sendable, Codable, Equatable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let totalTokens: Int

    public init(inputTokens: Int, outputTokens: Int, totalTokens: Int) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
    }
}

public struct BackendLLMCompletionMetrics: Sendable, Equatable {
    public let task: LLMTask
    public let model: String
    public let requestID: String
    public let usage: BackendLLMUsage
    public let latencyMilliseconds: Int
    public let firstTokenLatencyMilliseconds: Int?
    public let streamed: Bool

    public init(
        task: LLMTask,
        model: String,
        requestID: String,
        usage: BackendLLMUsage,
        latencyMilliseconds: Int,
        firstTokenLatencyMilliseconds: Int? = nil,
        streamed: Bool = false
    ) {
        self.task = task
        self.model = model
        self.requestID = requestID
        self.usage = usage
        self.latencyMilliseconds = latencyMilliseconds
        self.firstTokenLatencyMilliseconds = firstTokenLatencyMilliseconds
        self.streamed = streamed
    }
}

public struct BackendLLMProvider: LLMProvider {
    private struct Message: Codable, Sendable {
        let content: String
        let role: String
    }

    private struct RequestBody: Encodable, Sendable {
        let learningChat: LearningChatContext?
        let parentOperationId: UUID?
        let operationId: UUID
        let voiceLeaseId: UUID?
        let maxOutputTokens: Int
        let messages: [Message]
        let responseFormat: String
        let task: String
    }

    private struct Completion: Decodable, Sendable {
        let content: String
        let model: String?
        let requestId: String?
        let usage: BackendLLMUsage?
    }

    private struct Delta: Decodable {
        let text: String
    }

    private struct StreamMetadata: Decodable {
        let model: String
        let providerRequestId: String?
    }

    private struct StreamFailure: Decodable {
        let code: String
        let retryable: Bool
    }

    private let backend: BackendClient
    private let guestID: String?
    private let metricsObserver: (@Sendable (BackendLLMCompletionMetrics) async -> Void)?

    public init(
        backend: BackendClient,
        guestID: String? = nil
    ) {
        self.backend = backend
        self.guestID = guestID
        self.metricsObserver = nil
    }

    public init(
        backend: BackendClient,
        guestID: String?,
        metricsObserver: @escaping @Sendable (BackendLLMCompletionMetrics) async -> Void
    ) {
        self.backend = backend
        self.guestID = guestID
        self.metricsObserver = metricsObserver
    }

    public func modelID(for tier: LLMTier) -> String {
        "server-managed"
    }

    public func complete(_ request: LLMRequest) async throws -> String {
        let startedAt = Date()
        do {
            let body = try makeBody(request)
            let completion: Completion
            if let guestID {
                completion = try await backend.sendWithGuestAccess(
                    path: "/v1/ai/completions",
                    method: "POST",
                    body: body,
                    guestID: guestID
                )
            } else {
                completion = try await backend.send(
                    path: "/v1/ai/completions",
                    method: "POST",
                    body: body
                )
            }
            guard !completion.content.isEmpty else {
                throw LLMError.emptyResponse
            }
            if let model = completion.model,
               let requestID = completion.requestId,
               let usage = completion.usage,
               let metricsObserver {
                await metricsObserver(
                    BackendLLMCompletionMetrics(
                        task: request.task,
                        model: model,
                        requestID: requestID,
                        usage: usage,
                        latencyMilliseconds: max(
                            0,
                            Int(Date().timeIntervalSince(startedAt) * 1_000)
                        ),
                        streamed: false
                    )
                )
            }
            return completion.content
        } catch {
            throw Self.map(error)
        }
    }

    public func stream(
        _ request: LLMRequest
    ) async -> AsyncThrowingStream<LLMStreamEvent, Error> {
        let startedAt = Date()
        do {
            let body = try makeBody(request)
            let events: AsyncThrowingStream<BackendServerSentEvent, Error>
            if let guestID {
                events = try await backend.eventStreamWithGuestAccess(
                    path: "/v1/ai/stream",
                    body: body,
                    guestID: guestID
                )
            } else {
                events = try await backend.eventStream(
                    path: "/v1/ai/stream",
                    body: body
                )
            }
            return AsyncThrowingStream { continuation in
                let task = Task {
                    var receivedDone = false
                    var firstTokenAt: Date?
                    var metadata: StreamMetadata?
                    var usage: BackendLLMUsage?
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
                                    if firstTokenAt == nil {
                                        firstTokenAt = .now
                                    }
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
                                if failure.code == "AI_EMPTY_RESPONSE" { throw LLMError.emptyResponse }
                                throw LLMError.http(
                                    status: failure.retryable ? 503 : 400,
                                    message: failure.code
                                )
                            case "metadata":
                                metadata = try JSONDecoder().decode(
                                    StreamMetadata.self,
                                    from: Data(event.data.utf8)
                                )
                            case "usage":
                                usage = try JSONDecoder().decode(
                                    BackendLLMUsage.self,
                                    from: Data(event.data.utf8)
                                )
                            default:
                                continue
                            }
                        }
                        guard receivedDone else {
                            throw LLMError.invalidResponse("AI 流在完成事件前中断")
                        }
                        if let metadata,
                           let usage,
                           let metricsObserver {
                            let finishedAt = Date()
                            await metricsObserver(
                                BackendLLMCompletionMetrics(
                                    task: request.task,
                                    model: metadata.model,
                                    requestID: metadata.providerRequestId ?? "server-stream",
                                    usage: usage,
                                    latencyMilliseconds: max(
                                        0,
                                        Int(finishedAt.timeIntervalSince(startedAt) * 1_000)
                                    ),
                                    firstTokenLatencyMilliseconds: firstTokenAt.map {
                                        max(0, Int($0.timeIntervalSince(startedAt) * 1_000))
                                    },
                                    streamed: true
                                )
                            )
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
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let schemaData = try encoder.encode(schema)
            let schemaText = String(decoding: schemaData, as: UTF8.self)
            systemParts.insert(
                """
                只返回一个符合 schema“\(name)”的 JSON 对象，不添加 Markdown 或解释。
                JSON Schema：
                \(schemaText)
                """, at: 0
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
            learningChat: request.learningChat,
            parentOperationId: request.parentOperationID,
            operationId: request.operationID,
            voiceLeaseId: request.voiceLeaseID,
            maxOutputTokens: request.maxTokens,
            messages: messages,
            responseFormat: responseFormat,
            task: request.task.rawValue
        )
    }

    private static func map(_ error: Error) -> Error {
        guard let backendError = error as? BackendClientError else { return error }
        if ["AUXILIARY_BUDGET_EXHAUSTED", "CREDITS_EXHAUSTED", "OPERATION_FINALIZED", "USAGE_QUOTA_EXCEEDED", "VOICE_LEASE_EXPIRED", "LOGIN_REQUIRED", "GUEST_ALREADY_CLAIMED"].contains(backendError.code ?? "") {
            return LLMError.accessRestricted(backendError.errorDescription ?? "当前额度已用完，请查看用量与权益。")
        }
        if backendError.code == "AI_EMPTY_RESPONSE" { return LLMError.emptyResponse }
        switch backendError {
        case .api(_, _, _, let status):
            return LLMError.http(
                status: status,
                message: backendError.errorDescription ?? "云端 AI 暂时不可用"
            )
        case .invalidResponse:
            return LLMError.invalidResponse("后端 AI 响应无法解析")
        case .signedOut:
            return LLMError.http(status: 401, message: "云端 AI 暂时不可用")
        case .transport:
            return URLError(.networkConnectionLost)
        }
    }
}

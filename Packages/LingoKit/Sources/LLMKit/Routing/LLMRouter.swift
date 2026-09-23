import CoreKit
import Foundation

/// 按设置派发到当前供应商，并统一重试策略：429/5xx/网络错误指数退避重试 2 次。
/// 流式请求只在「尚未收到任何增量」时重试，避免重复输出。
public final class LLMRouter: LLMClient, Sendable {
    public typealias ConfigProvider = @Sendable () async throws -> LLMProviderConfig
    public typealias ClientProvider = @Sendable () async throws -> any LLMClient

    private let clientProvider: ClientProvider
    private let maxRetries: Int

    public init(maxRetries: Int = 2, configProvider: @escaping ConfigProvider) {
        self.maxRetries = maxRetries
        self.clientProvider = {
            try await configProvider().makeProvider()
        }
    }

    public init(client: any LLMClient, maxRetries: Int = 2) {
        self.maxRetries = maxRetries
        self.clientProvider = { client }
    }

    public func complete(_ request: LLMRequest) async throws -> String {
        let provider = try await currentClient()
        // Automatic learning tasks can retry on a later interaction; never amplify
        // one failed background review into several paid provider attempts.
        let retryLimit = [.coachReview, .learningReview, .memorySummary, .quiz].contains(request.task) ? 0 : maxRetries
        var attempt = 0
        while true {
            do {
                return try await provider.complete(request)
            } catch {
                guard Self.isRetryable(error), attempt < retryLimit else { throw error }
                attempt += 1
                Log.llm.warning("complete 失败，第 \(attempt) 次重试：\(error)")
                try await Task.sleep(nanoseconds: Self.backoffNanos(attempt: attempt))
            }
        }
    }

    public func stream(_ request: LLMRequest) async -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var attempt = 0
                var deliveredAnyDelta = false
                while true {
                    do {
                        let provider = try await self.currentClient()
                        for try await event in await provider.stream(request) {
                            if case .textDelta = event { deliveredAnyDelta = true }
                            continuation.yield(event)
                        }
                        continuation.finish()
                        return
                    } catch {
                        if !deliveredAnyDelta, Self.isRetryable(error), attempt < self.maxRetries {
                            attempt += 1
                            Log.llm.warning("stream 失败，第 \(attempt) 次重试：\(error)")
                            try? await Task.sleep(nanoseconds: Self.backoffNanos(attempt: attempt))
                            continue
                        }
                        continuation.finish(throwing: error)
                        return
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 设置页「测试连接」。
    public func testConnection() async throws -> String {
        let request = LLMRequest(
            task: .translation,
            tier: .fast,
            messages: [.user("Reply with exactly: OK")],
            maxTokens: 8
        )
        return try await complete(request)
    }

    public func modelID(for tier: LLMTier) async throws -> String {
        let client = try await currentClient()
        return (client as? any LLMProvider)?.modelID(for: tier) ?? "server-managed"
    }

    private func currentClient() async throws -> any LLMClient {
        try await clientProvider()
    }

    static func isRetryable(_ error: Error) -> Bool {
        if let llmError = error as? LLMError {
            return llmError.isRetryable
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .cannotConnectToHost, .dnsLookupFailed, .notConnectedToInternet:
                return true
            default:
                return false
            }
        }
        return false
    }

    static func backoffNanos(attempt: Int) -> UInt64 {
        let base = 0.8 * pow(2, Double(attempt - 1)) // 0.8s, 1.6s
        let jitter = Double.random(in: 0...0.3)
        return UInt64((base + jitter) * 1_000_000_000)
    }
}

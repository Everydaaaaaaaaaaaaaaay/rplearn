import CoreKit
import Foundation

/// 按设置派发到当前供应商，并统一重试策略：429/5xx/网络错误指数退避重试 2 次。
/// 流式请求只在「尚未收到任何增量」时重试，避免重复输出。
public final class LLMRouter: LLMClient, Sendable {
    public typealias ConfigProvider = @Sendable () async throws -> LLMProviderConfig
    public typealias ClientProvider = @Sendable () async throws -> any LLMClient

    private let clientProvider: ClientProvider
    private let maxRetries: Int
    private let deadlinePolicy: LLMDeadlinePolicy

    public init(maxRetries: Int = 2, deadlinePolicy: LLMDeadlinePolicy = .init(), configProvider: @escaping ConfigProvider) {
        self.maxRetries = maxRetries
        self.deadlinePolicy = deadlinePolicy
        self.clientProvider = {
            try await configProvider().makeProvider()
        }
    }

    public init(client: any LLMClient, maxRetries: Int = 2, deadlinePolicy: LLMDeadlinePolicy = .init()) {
        self.maxRetries = maxRetries
        self.deadlinePolicy = deadlinePolicy
        self.clientProvider = { client }
    }

    public func complete(_ request: LLMRequest) async throws -> String {
        try await AsyncDeadline.run(timeout: deadlinePolicy.completion) {
            try await self.completeWithRetries(request)
        }
    }

    private func completeWithRetries(_ request: LLMRequest) async throws -> String {
        try Task.checkCancellation()
        let provider = try await currentClient()
        // Automatic learning tasks can retry on a later interaction; never amplify
        // one failed background review into several paid provider attempts.
        let retryLimit = [.coachReview, .memorySummary].contains(request.task) ? 0 : maxRetries
        var attempt = 0
        while true {
            try Task.checkCancellation()
            do {
                let result = try await provider.complete(request)
                try Task.checkCancellation()
                return result
            } catch {
                try Task.checkCancellation()
                guard Self.isRetryable(error), attempt < retryLimit else { throw error }
                attempt += 1
                Log.llm.warning("complete 失败，第 \(attempt) 次重试：\(error)")
                try await Task.sleep(nanoseconds: Self.backoffNanos(attempt: attempt))
            }
        }
    }

    public func stream(_ request: LLMRequest) async -> AsyncThrowingStream<LLMStreamEvent, Error> {
        guard !Task.isCancelled else { return AsyncThrowingStream { $0.finish(throwing: CancellationError()) } }
        return AsyncThrowingStream { continuation in
            let progress = LLMStreamProgress()
            let task = Task {
                var attempt = 0
                var deliveredAnyDelta = false
                while !Task.isCancelled {
                    do {
                        try Task.checkCancellation()
                        let provider = try await self.currentClient()
                        try Task.checkCancellation()
                        for try await event in await provider.stream(request) {
                            try Task.checkCancellation()
                            if case .textDelta(let text) = event, !text.isEmpty {
                                deliveredAnyDelta = true
                                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { progress.recordToken() }
                            }
                            if case .terminated = continuation.yield(event) { return }
                            if event == .finished {
                                _ = progress.finish()
                                continuation.finish()
                                return
                            }
                        }
                        _ = progress.finish()
                        continuation.finish()
                        return
                    } catch {
                        guard !Task.isCancelled, !(error is CancellationError) else {
                            _ = progress.finish()
                            continuation.finish(throwing: CancellationError())
                            return
                        }
                        if !deliveredAnyDelta, Self.isRetryable(error), attempt < self.maxRetries {
                            attempt += 1
                            Log.llm.warning("stream 失败，第 \(attempt) 次重试：\(error)")
                            do { try await Task.sleep(nanoseconds: Self.backoffNanos(attempt: attempt)) }
                            catch { continuation.finish(throwing: CancellationError()); return }
                            continue
                        }
                        _ = progress.finish()
                        continuation.finish(throwing: error)
                        return
                    }
                }
                continuation.finish(throwing: CancellationError())
            }
            let watchdog = Task {
                while let remaining = progress.remaining(self.deadlinePolicy) {
                    if remaining <= .zero {
                        if progress.finish() { continuation.finish(throwing: URLError(.timedOut)) }
                        task.cancel()
                        return
                    }
                    do { try await Task.sleep(for: min(remaining, .milliseconds(250))) }
                    catch { return }
                }
            }
            continuation.onTermination = { _ in
                _ = progress.finish()
                task.cancel(); watchdog.cancel()
            }
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

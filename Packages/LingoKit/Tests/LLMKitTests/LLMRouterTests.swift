import Foundation
import Testing
@testable import LLMKit

@Suite("LLMRouter")
struct LLMRouterTests {
    private actor FailingClient: LLMClient {
        var calls = 0
        func complete(_ request: LLMRequest) async throws -> String {
            calls += 1
            throw URLError(.timedOut)
        }
        func stream(_ request: LLMRequest) async -> AsyncThrowingStream<LLMStreamEvent, Error> {
            AsyncThrowingStream { $0.finish() }
        }
    }

    @Test("后台失败不放大请求，前台保留重试", arguments: [LLMTask.coachReview, .memorySummary, .proactiveMessage, .conversation])
    func boundedRetries(task: LLMTask) async {
        let client = FailingClient()
        let router = LLMRouter(client: client, maxRetries: 1)
        _ = try? await router.complete(LLMRequest(task: task, tier: .fast, messages: [.user("hello")]))
        #expect(await client.calls == (task == .conversation ? 2 : 1))
    }

    @Test("可重试错误判定")
    func retryability() {
        #expect(LLMRouter.isRetryable(LLMError.http(status: 429, message: "")))
        #expect(LLMRouter.isRetryable(LLMError.http(status: 500, message: "")))
        #expect(LLMRouter.isRetryable(LLMError.http(status: 529, message: "")))
        #expect(!LLMRouter.isRetryable(LLMError.http(status: 400, message: "")))
        #expect(!LLMRouter.isRetryable(LLMError.missingAPIKey))
        #expect(LLMRouter.isRetryable(URLError(.timedOut)))
        #expect(!LLMRouter.isRetryable(URLError(.badURL)))
    }

    @Test("配置缺 Key 时 complete 抛 missingAPIKey")
    func missingKeySurfaces() async {
        let router = LLMRouter { throw LLMError.missingAPIKey }
        await #expect(throws: LLMError.missingAPIKey) {
            _ = try await router.complete(
                LLMRequest(task: .conversation, tier: .fast, messages: [.user("hi")])
            )
        }
    }

    private actor StreamingClient: LLMClient {
        enum Mode: Sendable { case silent, partial, active, finished, retry, setup }
        let mode: Mode
        private(set) var calls = 0
        var setupWaiter: CheckedContinuation<Void, Never>?
        func releaseSetup() { setupWaiter?.resume(); setupWaiter = nil }
        init(_ mode: Mode) { self.mode = mode }
        func complete(_ request: LLMRequest) async throws -> String { "OK" }
        func stream(_ request: LLMRequest) async -> AsyncThrowingStream<LLMStreamEvent, Error> {
            calls += 1
            if mode == .setup { await withCheckedContinuation { setupWaiter = $0 } }
            let mode = mode
            return AsyncThrowingStream { continuation in
                if mode == .retry { continuation.finish(throwing: URLError(.networkConnectionLost)); return }
                if mode == .partial { continuation.yield(.textDelta("A preserved partial.")) }
                if mode == .finished { continuation.yield(.textDelta("Done.")); continuation.yield(.finished) }
                let producer = Task {
                    do {
                        while true {
                            try await Task.sleep(for: .milliseconds(10))
                            if mode == .active { continuation.yield(.textDelta("more ")) }
                        }
                    } catch { }
                }
                continuation.onTermination = { _ in producer.cancel() }
            }
        }
    }

    @Test("首字、流中断和总时长均有上限，已收到的片段不重复请求", arguments: [0, 1, 2, 3])
    func streamDeadlines(scenario: Int) async {
        let client = StreamingClient([.silent, .partial, .active, .setup][scenario])
        let router = LLMRouter(client: client, maxRetries: 2,
            deadlinePolicy: .init(firstToken: .milliseconds(70), idle: .milliseconds(45), streamTotal: .milliseconds(130)))
        var text = ""
        let start = ContinuousClock.now
        do {
            for try await event in await router.stream(.init(task: .conversation, tier: .fast, messages: [])) {
                if case .textDelta(let part) = event { text += part }
            }
            Issue.record("Expected timeout")
        } catch { #expect((error as? URLError)?.code == .timedOut) }
        #expect(start.duration(to: .now) < .seconds(1))
        #expect(await client.calls == 1)
        await client.releaseSetup()
        if scenario == 1 { #expect(text == "A preserved partial.") }
    }

    @Test("收到 finished 即完成，不等待供应商连接关闭")
    func finishedDoesNotWaitForEOF() async throws {
        let client = StreamingClient(.finished)
        let router = LLMRouter(client: client, maxRetries: 0,
            deadlinePolicy: .init(firstToken: .milliseconds(200), idle: .milliseconds(200), streamTotal: .milliseconds(300)))
        var events = [LLMStreamEvent]()
        for try await event in await router.stream(.init(task: .conversation, tier: .fast, messages: [])) { events.append(event) }
        #expect(events == [.textDelta("Done."), .finished])
    }

    @Test("退避期间取消不会偷偷重发请求")
    func cancellingBackoffStopsRetries() async throws {
        let client = StreamingClient(.retry)
        let retrying = LLMRouter(client: client, maxRetries: 4)
        let task = Task {
            do { for try await _ in await retrying.stream(.init(task: .conversation, tier: .fast, messages: [])) { } }
            catch { }
        }
        for _ in 0..<50 {
            if await client.calls > 0 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        task.cancel()
        await task.value
        try await Task.sleep(for: .milliseconds(80))
        #expect(await client.calls == 1)
    }
}

import Foundation
import LLMKit
import Testing
@testable import DomainKit

@Suite("对话成长评价故障恢复")
struct ConversationLearningReviewerTests {
    private actor Client: LLMClient {
        var calls = 0
        var operations: [UUID] = []
        let outputs: [String]
        let failure: LLMError?
        init(_ outputs: [String] = [], failure: LLMError? = nil) { self.outputs = outputs; self.failure = failure }
        func complete(_ request: LLMRequest) async throws -> String {
            operations.append(request.operationID); calls += 1
            if let failure { throw failure }
            return outputs[min(calls - 1, outputs.count - 1)]
        }
        func stream(_ request: LLMRequest) async -> AsyncThrowingStream<LLMStreamEvent, Error> {
            AsyncThrowingStream { $0.finish() }
        }
    }
    private func sample() -> (ConversationLearningLedger.Attempt, UUID) {
        var ledger = ConversationLearningLedger()
        let attempt = ledger.begin(context: "饮料选择", character: "Ruby", day: 1, origin: .live)
        let id = UUID()
        ledger.observe(.sent(id: id, text: "I prefer tea because it is warm.", voice: false), attemptID: attempt)
        return (ledger.active!, id)
    }
    private func response(_ id: UUID) throws -> String {
        String(decoding: try JSONEncoder().encode(ConversationLearningLedger.Review(verdict: .complete, evidenceMessageIDs: [id], feedback: "意思清楚")), as: UTF8.self)
    }
    @Test("围栏 JSON 本地恢复，不额外调用模型")
    func fenced() async throws {
        let (attempt, id) = sample()
        let client = Client(["```json\n\(try response(id))\n```"])
        let result = try await ConversationLearningReviewer.review(attempt: attempt, llm: client)
        #expect(result.review.evidenceMessageIDs == [id])
        #expect(await client.calls == 1)
    }
    @Test("损坏返回只重试一次，使用新请求 ID")
    func malformedThenValid() async throws {
        let (attempt, id) = sample()
        let client = Client(["{truncated", try response(id)])
        let result = try await ConversationLearningReviewer.review(attempt: attempt, llm: client)
        #expect(result.calls == 2)
        #expect(await Set(client.operations).count == 2)
        #expect(attempt.phase == .active)
        #expect(attempt.awardedXP == 0)
    }
    @Test("虚构证据不能发奖，持续损坏也不无限重试")
    func forgedTwice() async throws {
        let (attempt, _) = sample()
        let client = Client([try response(UUID())])
        await #expect(throws: ConversationLearningLedger.Rejection.self) {
            try await ConversationLearningReviewer.review(attempt: attempt, llm: client)
        }
        #expect(await client.calls == 2)
    }
    @Test("鉴权、额度和限流不盲目重试", arguments: [401, 402, 403, 429])
    func restricted(status: Int) async {
        let (attempt, _) = sample()
        let client = Client(failure: .http(status: status, message: "restricted"))
        _ = try? await ConversationLearningReviewer.review(attempt: attempt, llm: client)
        #expect(await client.calls == 1)
    }
    @Test("上游临时错误最多两次")
    func upstreamFailure() async {
        let (attempt, _) = sample()
        let client = Client(failure: .http(status: 503, message: "unavailable"))
        _ = try? await ConversationLearningReviewer.review(attempt: attempt, llm: client)
        #expect(await client.calls == 2)
    }
    @Test("取消的评价不发送请求")
    func cancellation() async {
        let (attempt, _) = sample()
        let client = Client(["{}"])
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try? await ConversationLearningReviewer.review(attempt: attempt, llm: client)
        }
        _ = await task.value
        #expect(await client.calls == 0)
    }
}

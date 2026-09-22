import Foundation
import LLMKit
import Testing
@testable import DomainKit

@Suite("对话成长评价故障恢复")
struct ConversationLearningReviewerTests {
    private actor Client: LLMClient {
        var calls = 0
        var operations: [UUID] = []
        var payloads: [String] = []
        let outputs: [String]
        let failure: LLMError?
        init(_ outputs: [String] = [], failure: LLMError? = nil) { self.outputs = outputs; self.failure = failure }
        func complete(_ request: LLMRequest) async throws -> String {
            operations.append(request.operationID); calls += 1
            payloads.append(request.messages.first?.content ?? "")
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
        String(decoding: try JSONSerialization.data(withJSONObject: ["verdict": "complete", "wantsToStop": false, "evidenceMessageIDs": [id.uuidString], "feedback": "意思清楚", "choiceEnglish": "tea", "reasonEnglish": "it is warm"]), as: UTF8.self)
    }
    private func wire(_ review: ConversationLearningLedger.Review) throws -> String {
        var fields = try JSONSerialization.jsonObject(with: JSONEncoder().encode(review)) as! [String: Any]
        fields["wantsToStop"] = false
        return String(decoding: try JSONSerialization.data(withJSONObject: fields), as: UTF8.self)
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
    @Test("被窗口截掉的真实消息也不能作为本次评价证据")
    func excludedHistoricalEvidence() async throws {
        var ledger = ConversationLearningLedger()
        let attempt = ledger.begin(context: "weekend", character: "Ruby", day: 1, origin: .live)
        let historical = UUID()
        ledger.observe(.sent(id: historical, text: "The beach because it is quiet.", voice: false), attemptID: attempt)
        for _ in 0..<8 {
            ledger.observe(.sent(id: UUID(), text: "I have not decided yet.", voice: false), attemptID: attempt)
        }
        let client = Client([try response(historical)])
        await #expect(throws: ConversationLearningLedger.Rejection.self) {
            try await ConversationLearningReviewer.review(attempt: ledger.active!, llm: client)
        }
        #expect(await client.calls == 2)
        #expect(ledger.xp == 0)
    }
    @Test("空窗口不请求模型，包括只有超长消息")
    func emptyWindow() async {
        var ledger = ConversationLearningLedger()
        let id = ledger.begin(context: "weekend", character: "Ruby", day: 1, origin: .live)
        let client = Client(["{}"])
        _ = try? await ConversationLearningReviewer.review(attempt: ledger.active!, llm: client)
        ledger.observe(.sent(id: UUID(), text: String(repeating: "x", count: 8001), voice: false), attemptID: id)
        _ = try? await ConversationLearningReviewer.review(attempt: ledger.active!, llm: client)
        #expect(await client.calls == 0)
    }
    @Test("重复证据 ID 和超长反馈不能通过结构校验", arguments: [true, false])
    func invalidShape(duplicate: Bool) async throws {
        let (attempt, id) = sample()
        let invalid = ConversationLearningLedger.Review(verdict: .complete,
            evidenceMessageIDs: duplicate ? [id, id] : [id],
            feedback: duplicate ? "ok" : String(repeating: "a", count: 601))
        let client = Client([try wire(invalid)])
        await #expect(throws: ConversationLearningLedger.Rejection.self) {
            try await ConversationLearningReviewer.review(attempt: attempt, llm: client)
        }
        #expect(await client.calls == 2)
    }
    @Test("空白反馈触发有界恢复，避免完成却没有任何说明")
    func blankFeedback() async throws {
        let (attempt, id) = sample()
        let invalid = ConversationLearningLedger.Review(verdict: .complete, evidenceMessageIDs: [id], feedback: " \n\t ")
        let client = Client([try wire(invalid), try response(id)])
        let result = try await ConversationLearningReviewer.review(attempt: attempt, llm: client)
        #expect(result.calls == 2)
        #expect(!result.review.feedback.isEmpty)
    }
    @Test("完成必须引用真实英文，而非把中文悄悄翻译成证据", arguments: ["公园", "the park", ""])
    func translatedOrMissingProof(choice: String) async throws {
        var ledger = ConversationLearningLedger()
        let attempt = ledger.begin(context: "weekend", character: "Ruby", day: 1, origin: .live)
        let id = UUID()
        ledger.observe(.sent(id: id, text: "我选择公园 because it is near home.", voice: false), attemptID: attempt)
        let raw = String(decoding: try JSONSerialization.data(withJSONObject: [
            "verdict": "complete", "wantsToStop": false, "evidenceMessageIDs": [id.uuidString], "feedback": "完成",
            "choiceEnglish": choice, "reasonEnglish": "it is near home"]), as: UTF8.self)
        let client = Client([raw])
        let result = try await ConversationLearningReviewer.review(attempt: ledger.active!, llm: client)
        #expect(result.review.verdict == .uncertain)
        #expect(await client.calls == 2)
        try ledger.apply(result.review, attemptID: attempt, expectedRevision: ledger.revision)
        #expect(ledger.xp == 0)
        #expect(ledger.active != nil)
    }
    @Test("停止意愿优先于模型给出的完成标签")
    func stoppingOverridesCompletion() async throws {
        let (attempt, id) = sample()
        let raw = String(decoding: try JSONSerialization.data(withJSONObject: [
            "verdict": "complete", "wantsToStop": true, "evidenceMessageIDs": [id.uuidString],
            "feedback": "好的，我们先停在这里。", "choiceEnglish": "tea", "reasonEnglish": "it is warm"]), as: UTF8.self)
        let client = Client([raw])
        let result = try await ConversationLearningReviewer.review(attempt: attempt, llm: client)
        #expect(result.review.verdict == .needsSupport)
        #expect(result.calls == 1)
    }
    @Test("英文表达里的中文专名不应被整体拒绝")
    func properNameInsideEnglish() async throws {
        var ledger = ConversationLearningLedger()
        let attempt = ledger.begin(context: "weekend", character: "Ruby", day: 1, origin: .live)
        let id = UUID()
        ledger.observe(.sent(id: id, text: "I choose 北京 because I love its old buildings.", voice: false), attemptID: attempt)
        let raw = String(decoding: try JSONSerialization.data(withJSONObject: [
            "verdict": "complete", "wantsToStop": false, "evidenceMessageIDs": [id.uuidString],
            "feedback": "选择和理由清楚。", "choiceEnglish": "I choose 北京", "reasonEnglish": "I love its old buildings"]), as: UTF8.self)
        let result = try await ConversationLearningReviewer.review(attempt: ledger.active!, llm: Client([raw]))
        #expect(result.review.verdict == .complete)
    }
    @Test("连接词不冒充英文理由")
    func connectorIsNotReason() async throws {
        var ledger = ConversationLearningLedger()
        let attempt = ledger.begin(context: "weekend", character: "Ruby", day: 1, origin: .live)
        let id = UUID()
        ledger.observe(.sent(id: id, text: "I choose the beach because 那里很安静。", voice: false), attemptID: attempt)
        let raw = String(decoding: try JSONSerialization.data(withJSONObject: [
            "verdict": "complete", "wantsToStop": false, "evidenceMessageIDs": [id.uuidString],
            "feedback": "完成", "choiceEnglish": "the beach", "reasonEnglish": "because 那里很安静"]), as: UTF8.self)
        let result = try await ConversationLearningReviewer.review(attempt: ledger.active!, llm: Client([raw]))
        #expect(result.review.verdict == .uncertain)
        #expect(result.calls == 2)
    }
    @Test("NPC 上下文可解释指代，但不能冒充用户的理由")
    func partnerCannotSupplyEvidence() async throws {
        var ledger = ConversationLearningLedger()
        let attempt = ledger.begin(context: "weekend", character: "Ruby", day: 1, origin: .live)
        let id = UUID()
        ledger.observe(.sent(id: id, text: "Yes.", voice: false), attemptID: attempt)
        let raw = String(decoding: try JSONSerialization.data(withJSONObject: [
            "verdict": "complete", "wantsToStop": false, "evidenceMessageIDs": [id.uuidString],
            "feedback": "完成", "choiceEnglish": "Yes", "reasonEnglish": "it is close"]), as: UTF8.self)
        let result = try await ConversationLearningReviewer.review(attempt: ledger.active!, llm: Client([raw]),
            precedingPartnerText: [id: "Would you choose the park because it is close?"])
        #expect(result.review.verdict == .uncertain)
        #expect(result.calls == 2)
    }
    @Test("上下文仅保留送审用户消息对应部分，长度有界")
    func partnerContextIsBounded() async throws {
        var ledger = ConversationLearningLedger()
        let attempt = ledger.begin(context: "weekend", character: "Ruby", day: 1, origin: .live)
        var prompts: [UUID: String] = [UUID(): "UNRELATED_PRIVATE_CONTEXT"]
        for _ in 0..<8 {
            let id = UUID()
            ledger.observe(.sent(id: id, text: "The park because it is close.", voice: false), attemptID: attempt)
            prompts[id] = String(repeating: "x", count: 3000)
        }
        let id = ledger.active!.turns.last!.id
        let raw = String(decoding: try JSONSerialization.data(withJSONObject: [
            "verdict": "needsSupport", "wantsToStop": false, "evidenceMessageIDs": [id.uuidString],
            "feedback": "再说说看", "choiceEnglish": "", "reasonEnglish": ""]), as: UTF8.self)
        let client = Client([raw])
        _ = try await ConversationLearningReviewer.review(attempt: ledger.active!, llm: client, precedingPartnerText: prompts)
        let input = await client.payloads[0]
        #expect(!input.contains("UNRELATED_PRIVATE_CONTEXT"))
        let records = try JSONSerialization.jsonObject(with: Data(input.utf8)) as! [[String: Any]]
        let sizes = records.compactMap { ($0["precedingPartnerText"] as? String)?.count }
        #expect(sizes.reduce(0, +) == 1800)
        #expect(sizes.allSatisfy { $0 <= 600 })
        #expect(records.count == 8)
    }
}

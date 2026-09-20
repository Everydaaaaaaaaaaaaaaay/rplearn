import LLMKit
import Testing
@testable import DomainKit

@Suite("TranslationService")
struct TranslationServiceTests {
    @Test("翻译走 balanced 档、低温采样，输出去除首尾空白")
    func requestShape() async throws {
        let mock = MockLLMProvider(completeHandler: { request in
            #expect(request.task == .translation)
            #expect(request.tier == .balanced)
            #expect(request.temperature == 0.3)
            #expect(request.system?.contains("翻译") == true)
            #expect(request.messages == [.user("Fancy a pint later?")])
            return "\n待会儿去喝一杯？  "
        })
        let service = TranslationService(llm: mock)
        let result = try await service.translateToChinese("Fancy a pint later?")
        #expect(result == "待会儿去喝一杯？")
    }
    @Test("失败和空译文均重试，第三次成功")
    func retriesErrorsAndEmptyResults() async throws {
        let attempts = TranslationAttempts(outputs: [nil, "  ", "译文"])
        let service = TranslationService(llm: MockLLMProvider(completeHandler: { _ in
            try await attempts.next()
        }), retryDelay: .zero)
        #expect(try await service.translateToChinese("Hello") == "译文")
        #expect(await attempts.count == 3)
    }

    @Test("三次失败才抛错，由调用方使用 Apple 兜底")
    func exhaustedRetries() async {
        let attempts = TranslationAttempts(outputs: [nil, nil, nil])
        let service = TranslationService(llm: MockLLMProvider(completeHandler: { _ in
            try await attempts.next()
        }), retryDelay: .zero)
        do {
            _ = try await service.translateToChinese("Hello")
            Issue.record("Expected exhausted retries")
        } catch {}
        #expect(await attempts.count == 3)
    }

    @Test("取消翻译不再重试")
    func cancelledRequestStops() async {
        let attempts = TranslationAttempts(outputs: [nil, nil, nil])
        let service = TranslationService(llm: MockLLMProvider(completeHandler: { _ in
            try await attempts.next()
        }), retryDelay: .seconds(10))
        let task = Task { try await service.translateToChinese("Hello") }
        task.cancel()
        do { _ = try await task.value; Issue.record("Expected cancellation") } catch {}
        #expect(await attempts.count <= 1)
    }

}

private actor TranslationAttempts {
    var count = 0
    let outputs: [String?]
    init(outputs: [String?]) { self.outputs = outputs }
    func next() throws -> String {
        let result = outputs[min(count, outputs.count - 1)]
        count += 1
        guard let result else { throw TestFailure.failed }
        return result
    }
    enum TestFailure: Error { case failed }
}

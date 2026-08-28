import LLMKit
import Testing
@testable import DomainKit

@Suite("TranslationService")
struct TranslationServiceTests {
    @Test("翻译走 balanced 档、低温采样，输出去除首尾空白")
    func requestShape() async throws {
        let mock = MockLLMProvider(completeHandler: { request in
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
}

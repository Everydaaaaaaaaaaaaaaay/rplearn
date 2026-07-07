import Foundation
import LLMKit

/// 零网络的 LLMProvider 替身，供全部领域服务单测注入。
struct MockLLMProvider: LLMProvider {
    var completeHandler: @Sendable (LLMRequest) async throws -> String = { _ in "OK" }
    var streamEvents: [LLMStreamEvent] = [.textDelta("OK"), .finished]

    func complete(_ request: LLMRequest) async throws -> String {
        try await completeHandler(request)
    }

    func stream(_ request: LLMRequest) async -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            for event in streamEvents {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }

    func modelID(for tier: LLMTier) -> String {
        "mock-\(tier.rawValue)"
    }
}

#if DEBUG
import LLMKit

struct DebugChatTimelineProvider: LLMClient {
    func complete(_ request: LLMRequest) async throws -> String {
        """
        {"coach_review":{"has_issues":false,"issues":[]},"relationship":{"warmth":0,"responsiveness":0,"respect":0,"empathy":0,"reciprocity":0,"disclosure":0,"resonance":0,"engagement":0,"boundary_harm":0,"repair":0,"significance":0,"confidence":0,"reason_zh":""},"growth":null,"memory_facts":[]}
        """
    }

    func stream(_ request: LLMRequest) async -> AsyncThrowingStream<LLMStreamEvent, Error> {
        let text = request.messages.last(where: { $0.role == .user })?.content ?? ""
        let reply: String
        if text.contains("How are you doing") {
            reply = "I feel really sad today."
        } else if text.contains("How was your walk") {
            reply = "I feel really sad after the walk."
        } else if text.contains("Was your sister angry") {
            reply = "My sister was furious about the train."
        } else if text.contains("Did it work out") {
            reply = "I feel really happy that it worked out."
        } else {
            reply = "The river was quiet this morning."
        }
        return AsyncThrowingStream { continuation in
            continuation.yield(.textDelta(reply))
            continuation.yield(.finished)
            continuation.finish()
        }
    }
}
#endif

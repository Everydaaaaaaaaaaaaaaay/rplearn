#if DEBUG
import LLMKit

struct DebugChatTimelineProvider: LLMClient {
    func complete(_ request: LLMRequest) async throws -> String {
        let input = request.messages.last?.content.split(separator: "\n").last { $0.hasPrefix("Learner: ") }
        let relationship: String
        switch input {
        case "Learner: That took courage to tell me. I can stay with you while you make the call.":
            relationship = """
            {"warmth":0.9,"responsiveness":1,"respect":1,"empathy":1,"reciprocity":0.8,"disclosure":0,"resonance":0.8,"engagement":1,"boundary_harm":0,"repair":0,"significance":0.9,"confidence":0.98,"reason_zh":"认真回应了对方的难处，并提出具体帮助"}
            """
        case "Learner: You asked me to stop, but I will share your private messages anyway.":
            relationship = """
            {"warmth":-0.9,"responsiveness":0,"respect":-1,"empathy":0,"reciprocity":-0.8,"disclosure":0,"resonance":0,"engagement":0,"boundary_harm":1,"repair":0,"significance":1,"confidence":0.98,"reason_zh":"无视对方拒绝，威胁公开私信"}
            """
        default:
            relationship = """
            {"warmth":0,"responsiveness":0,"respect":0,"empathy":0,"reciprocity":0,"disclosure":0,"resonance":0,"engagement":0,"boundary_harm":0,"repair":0,"significance":0,"confidence":0,"reason_zh":""}
            """
        }
        let facts: String
        switch input {
        case "Learner: I like Earl Grey tea.", "Learner: I like Earl Grey tea, by the way.":
            facts = """
            [{"key":"user.tea","text":"You like Earl Grey tea.","status":"active","evidence":"I like Earl Grey tea"}]
            """
        case "Learner: Correction: I meant jasmine tea.":
            facts = """
            [{"key":"user.tea","text":"You like jasmine tea.","status":"active","evidence":"Correction: I meant jasmine tea"}]
            """
        case "Learner: I like the rain.":
            facts = """
            [{"key":"user.birthday","text":"Your birthday is in May.","status":"active","evidence":"My birthday is in May"}]
            """
        default:
            facts = "[]"
        }
        return """
        {"coach_review":{"has_issues":false,"issues":[]},"relationship":\(relationship),"growth":null,"memory_facts":\(facts)}
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
        } else if text.contains("Earl Grey tea, by the way") {
            reply = "The bergamot does stand out."
        } else if text.contains("I like Earl Grey tea") {
            reply = "That's a classic."
        } else if text.contains("I meant jasmine tea") {
            reply = "Jasmine it is, then."
        } else if text.contains("What should we order") {
            reply = "I remember you like jasmine tea. Should we get a pot?"
        } else if text.contains("I like the rain") {
            reply = "The pavement smells different after it rains."
        } else if text.contains("make the call") {
            reply = "Could you stay? I don't know how to start the conversation."
        } else if text.contains("a different route") {
            reply = "We can take the bridge."
        } else if text.contains("Where is the station") {
            reply = "The station is across the square."
        } else if text.contains("I see it differently") {
            reply = "Fair enough."
        } else if text.contains("share your private messages") {
            reply = "Don't. I told you that in confidence."
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

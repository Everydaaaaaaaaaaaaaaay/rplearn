import Foundation
import LLMKit
import Testing
@testable import DomainKit

@Suite("量化评价证据契约")
struct LearningSystemReviewerTests {
    struct Client: LLMClient {
        let output: String
        func complete(_ request: LLMRequest) async throws -> String { output }
        func stream(_ request: LLMRequest) async -> AsyncThrowingStream<LLMStreamEvent, Error> { AsyncThrowingStream { $0.finish() } }
    }
    @Test func rejectsFabricationAndOutOfRangeScores() async throws {
        let id = UUID(), text = "Tea because it is warm."
        for (quote, scores, cited) in [("Tea", [2,2,1,1],UUID()),("Coffee",[2,2,1,1],id),("Tea",[3,2,1,1],id)] {
            let raw = try JSONSerialization.data(withJSONObject:["paused":false,"assessments":[["skill":"preference","band":1,"topic":"food","scores":scores,"messageIDs":[cited.uuidString],"quote":quote,"explanation":"说明了理由"]]])
            await #expect(throws: ConversationLearningLedger.Rejection.self) {
                try await LearningSystemReviewer.assess(turns:[.init(id:id,text:text)],context:"",llm:Client(output:String(decoding:raw,as:UTF8.self)))
            }
        }
    }
    @Test func noOpportunityIsNotFailure() async throws {
        let result = try await LearningSystemReviewer.assess(turns:[.init(id:UUID(),text:"Hi")],context:"",llm:Client(output:"{\"paused\":false,\"assessments\":[]}"))
        #expect(result.assessments.isEmpty)
    }
    @Test func groundedAssessmentRetainsSeparateDimensions() async throws {
        let id=UUID()
        let raw=try JSONSerialization.data(withJSONObject:["paused":false,"assessments":[["skill":"preference","band":1,"topic":"food","scores":[2,2,1,1],"messageIDs":[id.uuidString],"quote":"Tea because it is warm.","explanation":"说清了选择和理由"]]])
        let result=try await LearningSystemReviewer.assess(turns:[.init(id:id,text:"Tea because it is warm.")],context:"What would you like?",llm:Client(output:String(decoding:raw,as:UTF8.self)))
        #expect(result.assessments.first?.scores == [2,2,1,1])
    }
}

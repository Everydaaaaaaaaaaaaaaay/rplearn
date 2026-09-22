import Foundation
import LLMKit
import Testing
@testable import DomainKit

@Suite("量化评价证据契约")
struct LearningSystemReviewerTests {
    struct Client: LLMClient {
        let output: String
        func complete(_ request: LLMRequest) async throws -> String {
            guard case .jsonSchema = request.responseFormat else {
                Issue.record("Learning assessment must request structured JSON")
                return output
            }
            return output
        }
        func stream(_ request: LLMRequest) async -> AsyncThrowingStream<LLMStreamEvent, Error> { AsyncThrowingStream { $0.finish() } }
    }
    @Test func rejectsFabricationAndOutOfRangeScores() async throws {
        let id = UUID(), text = "Tea because it is warm."
        for (quote, scores, cited) in [("Tea", [2,2,1,1],UUID()),("Coffee",[2,2,1,1],id),("Tea",[3,2,1,1],id)] {
            let raw = try JSONSerialization.data(withJSONObject:["paused":false,"assessments":[["skill":"preference","band":1,"topic":"food","scores":scores,"messageIDs":[(cited == id ? "m1" : "m999")],"quote":quote,"explanation":"说明了理由","supports":[["requirement":"choice","quote":"Tea"],["requirement":"reason","quote":"because it is warm."]]]]])
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
        let raw=try JSONSerialization.data(withJSONObject:["paused":false,"assessments":[["skill":"preference","band":1,"topic":"food","scores":[2,2,1,1],"messageIDs":["m1"],"quote":"Tea because it is warm.","explanation":"说清了选择和理由","supports":[["requirement":"choice","quote":"Tea"],["requirement":"reason","quote":"because it is warm."]]]]])
        let result=try await LearningSystemReviewer.assess(turns:[.init(id:id,text:"Tea because it is warm.")],context:"What would you like?",llm:Client(output:String(decoding:raw,as:UTF8.self)))
        #expect(result.assessments.first?.scores == [2,2,1,1])
    }
    @Test func completeTaskRequiresEveryGroundedEnglishComponent() async throws {
        let id = UUID(), text = "我选择公园 because it is quiet."
        let variants: [[[String:String]]] = [
            [],
            [["requirement":"reason","quote":"because it is quiet."]],
            [["requirement":"choice","quote":"我选择公园"],["requirement":"reason","quote":"because it is quiet."]],
            [["requirement":"choice","quote":"I choose the park"],["requirement":"reason","quote":"because it is quiet."]]
        ]
        for supports in variants {
            let raw = try JSONSerialization.data(withJSONObject: ["paused":false,"assessments":[["skill":"preference","band":1,"topic":"travel","scores":[2,2,2,2],"messageIDs":["m1"],"quote":"because it is quiet.","explanation":"test","supports":supports]]])
            await #expect(throws: ConversationLearningLedger.Rejection.self) {
                try await LearningSystemReviewer.assess(turns: [.init(id:id,text:text)],context:"",llm:Client(output:String(decoding:raw,as:UTF8.self)))
            }
        }
    }
    @Test func bilingualCommentDoesNotInvalidateCompleteEnglish() async throws {
        let id = UUID(), text = "I choose the park because it is quiet. 我喜欢公园。"
        let raw = try JSONSerialization.data(withJSONObject:["paused":false,"assessments":[["skill":"preference","band":1,"topic":"travel","scores":[2,2,2,2],"messageIDs":["m1"],"quote":"I choose the park because it is quiet.","explanation":"test","supports":[["requirement":"choice","quote":"I choose the park"],["requirement":"reason","quote":"because it is quiet."]]]]])
        let result = try await LearningSystemReviewer.assess(turns:[.init(id:id,text:text)],context:"",llm:Client(output:String(decoding:raw,as:UTF8.self)))
        #expect(result.assessments.first?.scores.first == 2)
    }

    @Test func multilineEnglishAndNumericTimeRemainValid() async throws {
        let id = UUID(), text = "I'll visit the park.\n10:00"
        let raw = try JSONSerialization.data(withJSONObject:["paused":false,"assessments":[["skill":"planning","band":1,"topic":"travel","scores":[2,2,2,2],"messageIDs":["m1"],"quote":text,"explanation":"test","supports":[["requirement":"intended_action","quote":text],["requirement":"time_or_place","quote":"10:00"]]]]])
        let result = try await LearningSystemReviewer.assess(turns:[.init(id:id,text:text)],context:"",llm:Client(output:String(decoding:raw,as:UTF8.self)))
        #expect(result.assessments.first?.scores.first == 2)
    }

    @Test func shortIdentifiersResolveToOriginalMessages() async throws {
        let first = UUID(), second = UUID()
        let raw = #"{"paused":false,"assessments":[{"skill":"preference","band":1,"topic":"travel","scores":[2,2,2,2],"messageIDs":["m1","m2"],"quote":"The park.","explanation":"有选择和理由","supports":[{"requirement":"choice","quote":"The park."},{"requirement":"reason","quote":"Because it is near."}]}]}"#
        let result = try await LearningSystemReviewer.assess(turns: [.init(id:first,text:"The park."),.init(id:second,text:"Because it is near.")], context:"",llm:Client(output:raw))
        #expect(result.assessments.first?.messageIDs == [first, second])
    }
    @Test func mergedAndWrongBandKeysAreRejected() async throws {
        let task = try #require(LearningTask.bank.first { $0.skill == .planning && $0.band == 2 && $0.topic == "travel" })
        for key in ["first_action,second_action", "intended_action"] {
            let raw = try JSONSerialization.data(withJSONObject:["paused":false,"assessments":[["skill":"planning","band":2,"topic":"travel","scores":[1,2,1,2],"messageIDs":["m1"],"quote":"I'll visit the park tomorrow.","explanation":"只有一个安排","supports":[["requirement":key,"quote":"I'll visit the park tomorrow."]]]]])
            await #expect(throws: ConversationLearningLedger.Rejection.self) {
                try await LearningSystemReviewer.assess(turns:[.init(id:UUID(),text:"I'll visit the park tomorrow.")],context:"",task:task,llm:Client(output:String(decoding:raw,as:UTF8.self)))
            }
        }
    }

    @Test func retryPolicyDistinguishesRecoverableFailures() {
        #expect(LearningSystemReviewer.isRetryable(LLMError.invalidResponse("invalid test JSON")))
        #expect(LearningSystemReviewer.isRetryable(ConversationLearningLedger.Rejection.invalidEvidence))
        #expect(LearningSystemReviewer.isRetryable(URLError(.timedOut)))
        #expect(!LearningSystemReviewer.isRetryable(URLError(.notConnectedToInternet)))
        #expect(!LearningSystemReviewer.isRetryable(CancellationError()))
    }

    @Test func explicitTaskOwnsTopicMetadata() async throws {
        let task = try #require(LearningTask.bank.first { $0.skill == .experience && $0.band == 1 && $0.topic == "travel" })
        let raw = #"{"paused":false,"assessments":[{"skill":"experience","band":1,"topic":"daily_life","scores":[2,2,2,2],"messageIDs":["m1"],"quote":"Yesterday I visited the park and saw a dog.","explanation":"有过去经历和细节","supports":[{"requirement":"past_event","quote":"Yesterday I visited the park"},{"requirement":"detail","quote":"saw a dog"}]}]}"#
        let result = try await LearningSystemReviewer.assess(turns:[.init(id:UUID(),text:"Yesterday I visited the park and saw a dog.")],context:"",task:task,llm:Client(output:raw))
        #expect(result.assessments.first?.topic == "travel")
    }

    @Test func originalScriptNamesRequireEnglishFraming() async throws {
        for (text, choice, reason, names, accepted) in [
            ("I choose 西湖 because it is quiet.", "I choose 西湖", "because it is quiet", ["西湖"], true),
            ("I choose 西湖 because it is quiet.", "I choose 西湖", "because it is quiet", ["西湖","王老师"], true),
            ("我选择公园 because it is quiet.", "我选择公园", "because it is quiet", ["我选择公园"], false),
            ("I choose tea because那里安静。", "I choose tea", "because那里安静", ["那里安静"], false)
        ] {
            let supports: [[String:Any]] = [
                ["requirement":"choice","quote":choice,"names":choice.contains("西湖") || choice.hasPrefix("我") ? names : []],
                ["requirement":"reason","quote":reason,"names":reason.contains("那里") ? names : []]]
            let raw = try JSONSerialization.data(withJSONObject:["paused":false,"assessments":[["skill":"preference","band":1,"topic":"travel","scores":[2,2,2,2],"messageIDs":["m1"],"quote":text,"explanation":"测试专名依据","supports":supports]]])
            do {
                _ = try await LearningSystemReviewer.assess(turns:[.init(id:UUID(),text:text)],context:"",llm:Client(output:String(decoding:raw,as:UTF8.self)))
                #expect(accepted)
            } catch { #expect(!accepted) }
        }
    }

}

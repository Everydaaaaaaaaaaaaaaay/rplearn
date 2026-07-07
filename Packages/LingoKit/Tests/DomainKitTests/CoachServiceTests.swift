import Foundation
import LLMKit
import Testing
@testable import DomainKit

@Suite("CoachService")
struct CoachServiceTests {
    @Test("请求形状：fast 档、低温、JSON 结构化输出")
    func requestShape() async throws {
        let mock = MockLLMProvider(completeHandler: { request in
            #expect(request.tier == .fast)
            #expect(request.temperature == 0.2)
            if case .jsonSchema(let name, _) = request.responseFormat {
                #expect(name == "coach_review")
            } else {
                Issue.record("应使用 jsonSchema 输出")
            }
            return #"{"has_issues":true,"issues":[{"quote":"I very like","type":"grammar","correction":"I really like","explanation_zh":"very 不能直接修饰动词"}]}"#
        })
        let coach = CoachService(llm: mock)
        let review = try await coach.review(userText: "I very like football")
        #expect(review.hasIssues)
        #expect(review.issues.count == 1)
        #expect(review.issues.first?.correction == "I really like")
        #expect(review.issues.first?.explanationZh.contains("very") == true)
    }

    @Test("无错误时 has_issues=false")
    func noIssues() async throws {
        let mock = MockLLMProvider(completeHandler: { _ in
            #"{"has_issues":false,"issues":[]}"#
        })
        let review = try await CoachService(llm: mock).review(userText: "sounds great, see you at 7")
        #expect(!review.hasIssues)
        #expect(review.issues.isEmpty)
    }

    @Test("超时抛错（调用方静默放弃）")
    func timeout() async {
        let mock = MockLLMProvider(completeHandler: { _ in
            try await Task.sleep(for: .milliseconds(300))
            return #"{"has_issues":false,"issues":[]}"#
        })
        let coach = CoachService(llm: mock, timeout: .milliseconds(50))
        await #expect(throws: Error.self) {
            _ = try await coach.review(userText: "hello")
        }
    }

    @Test("coachReviewJSON 编解码往返")
    func persistenceRoundTrip() {
        let review = CoachReview(
            hasIssues: true,
            issues: [.init(quote: "a", type: "spelling", correction: "b", explanationZh: "拼写")]
        )
        let json = CoachService.encode(review)
        #expect(json != nil)
        #expect(CoachService.decode(fromJSON: json) == review)
        #expect(CoachService.decode(fromJSON: nil) == nil)
    }

    @Test("容忍模型输出包裹围栏")
    func fencedOutput() async throws {
        let mock = MockLLMProvider(completeHandler: { _ in
            """
            ```json
            {"has_issues":false,"issues":[]}
            ```
            """
        })
        let review = try await CoachService(llm: mock).review(userText: "hi")
        #expect(!review.hasIssues)
    }
}

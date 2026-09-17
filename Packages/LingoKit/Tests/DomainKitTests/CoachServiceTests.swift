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
            #expect(request.system?.contains("Gugu") == true)
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

    @Test("对不上原文的引用（上文旧错句）不显示")
    func staleQuoteIsDropped() async throws {
        let mock = MockLLMProvider(completeHandler: { _ in
            #"{"has_issues":true,"issues":[{"quote":"Feels like you want put all the sweet","type":"grammar","correction":"Feels like you want to put all the sweet things","explanation_zh":"want 后接动词需用不定式"}]}"#
        })
        let review = try await CoachService(llm: mock).review(userText: "Received the order, madam")
        #expect(!review.hasIssues)
        #expect(review.issues.isEmpty)
    }

    @Test("只保留能定位到的问题，大小写与空白差异不影响")
    func partialQuotesAreGrounded() async throws {
        let mock = MockLLMProvider(completeHandler: { _ in
            """
            {"has_issues":true,"issues":[\
            {"quote":"want put all the sweet","type":"grammar","correction":"want to put all the sweet things","explanation_zh":"want 后接不定式"},\
            {"quote":"i   very LIKE","type":"grammar","correction":"I really like","explanation_zh":"really 修饰动词"}]}
            """
        })
        let review = try await CoachService(llm: mock).review(userText: "I very like football")
        #expect(review.hasIssues)
        #expect(review.issues.map(\.quote) == ["i   very LIKE"])
    }

    @Test("模型判定没有错误时保持沉默")
    func explicitNoIssuesWins() {
        let review = CoachReview(
            hasIssues: false,
            issues: [.init(quote: "very like", type: "grammar", correction: "really like", explanationZh: "really 修饰动词")]
        )
        let grounded = review.grounded(inLearnerMessage: "I very like football")
        #expect(!grounded.hasIssues)
        #expect(grounded.issues.isEmpty)
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

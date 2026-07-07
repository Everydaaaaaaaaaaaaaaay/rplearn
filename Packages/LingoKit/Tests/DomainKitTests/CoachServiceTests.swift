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

    // MARK: - 口语点评（2.8）

    @Test("口语点评：请求形状 + 解析评分/点评/建议")
    func speechReviewShape() async throws {
        let mock = MockLLMProvider(completeHandler: { request in
            #expect(request.tier == .fast)
            if case .jsonSchema(let name, _) = request.responseFormat {
                #expect(name == "speech_review")
            } else {
                Issue.record("应使用 jsonSchema 输出")
            }
            return #"{"rating":4,"comment_zh":"说得挺流利的，继续保持！","tips":[{"quote":"how to say","better":"how do you say","explanation_zh":"口语里更习惯用 how do you say"}]}"#
        })
        let review = try await CoachService(llm: mock).reviewSpeech(transcript: "how to say this in english")
        #expect(review.rating == 4)
        #expect(review.commentZh.contains("流利"))
        #expect(review.tips.count == 1)
        #expect(review.tips.first?.better == "how do you say")
    }

    @Test("口语点评：无建议时 tips 为空")
    func speechReviewNoTips() async throws {
        let mock = MockLLMProvider(completeHandler: { _ in
            #"{"rating":5,"comment_zh":"非常自然！","tips":[]}"#
        })
        let review = try await CoachService(llm: mock).reviewSpeech(transcript: "sounds good, see you tomorrow")
        #expect(review.rating == 5)
        #expect(review.tips.isEmpty)
        #expect(review.clampedRating == 5)
    }

    @Test("口语点评：超时抛错（调用方静默放弃）")
    func speechReviewTimeout() async {
        let mock = MockLLMProvider(completeHandler: { _ in
            try await Task.sleep(for: .milliseconds(300))
            return #"{"rating":3,"comment_zh":"x","tips":[]}"#
        })
        let coach = CoachService(llm: mock, timeout: .milliseconds(50))
        await #expect(throws: Error.self) {
            _ = try await coach.reviewSpeech(transcript: "hello there")
        }
    }

    @Test("speechReviewJSON 编解码往返 + 评分钳制")
    func speechPersistenceRoundTrip() {
        let review = SpeechReview(
            rating: 9, // 越界
            commentZh: "不错",
            tips: [.init(quote: "a", better: "b", explanationZh: "更自然")]
        )
        let json = CoachService.encode(review)
        #expect(json != nil)
        #expect(CoachService.decodeSpeech(fromJSON: json) == review)
        #expect(CoachService.decodeSpeech(fromJSON: nil) == nil)
        #expect(review.clampedRating == 5)
    }
}

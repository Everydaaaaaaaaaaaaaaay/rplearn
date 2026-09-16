import Foundation
import Testing
import LLMKit
import PersistenceKit
@testable import DomainKit

@Suite("QuizService")
struct QuizServiceTests {
    private let validReply = """
    Ha, good question! We'd usually say "I'm keen on it".
    <quiz>{"question":"Which word means very tired?","options":["keen","exhausted","brave","tidy"],"answer":1,"explanation_zh":"exhausted 表示筋疲力尽。"}</quiz>
    """

    @Test("兜底出题请求包含实际水平而不是模板代码", arguments: [DifficultyLevel.primary1, .advanced])
    func fallbackRespectsLearnerLevel(level: DifficultyLevel) async throws {
        let client = MockLLMProvider(completeHandler: { request in
            #expect(request.system?.contains(PromptBuilder.languageGuidance(for: level)) == true)
            #expect(request.system?.contains("PromptBuilder.languageGuidance") == false)
            return """
            {"question":"Which word means tired?","options":["exhausted","keen","brave","tidy"],"answer":0,"explanation_zh":"exhausted 表示疲惫。"}
            """
        })
        let quiz = try await QuizService.generate(history: [], learnerDifficulty: level, using: client)
        #expect(quiz.answer == 0)
    }

    @Test("双开关 + 阈值触发判定")
    func triggerGate() {
        // 都开、达到阈值 → 触发
        #expect(QuizService.shouldRequestQuiz(globallyEnabled: true, conversationOptedOut: false, turnsSinceQuiz: 6, threshold: 6))
        // 未达阈值 → 不触发
        #expect(!QuizService.shouldRequestQuiz(globallyEnabled: true, conversationOptedOut: false, turnsSinceQuiz: 5, threshold: 6))
        // 全局关 → 不触发
        #expect(!QuizService.shouldRequestQuiz(globallyEnabled: false, conversationOptedOut: false, turnsSinceQuiz: 9, threshold: 6))
        // 本会话退订 → 不触发
        #expect(!QuizService.shouldRequestQuiz(globallyEnabled: true, conversationOptedOut: true, turnsSinceQuiz: 9, threshold: 6))
    }

    @Test("阈值 N=6±2")
    func threshold() {
        #expect(QuizService.nextThreshold(random: -2) == 4)
        #expect(QuizService.nextThreshold(random: 0) == 6)
        #expect(QuizService.nextThreshold(random: 2) == 8)
    }

    @Test("从回复末尾截取 quiz，正文去掉标记")
    func extractSuccess() {
        let (text, quiz) = QuizService.extract(from: validReply)
        #expect(!text.contains("<quiz>"))
        #expect(text.contains("keen on it"))
        #expect(quiz != nil)
        #expect(quiz?.answer == 1)
        #expect(quiz?.options.count == 4)
        #expect(quiz?.explanationZh.contains("筋疲力尽") == true)
    }

    @Test("无 quiz 标记：原样返回、quiz 为 nil")
    func extractNoQuiz() {
        let (text, quiz) = QuizService.extract(from: "Just a normal reply, no quiz here.")
        #expect(text == "Just a normal reply, no quiz here.")
        #expect(quiz == nil)
    }

    @Test("quiz JSON 损坏：正文保留、静默放弃 quiz")
    func extractBrokenJSON() {
        let reply = "Sure thing!<quiz>{not valid json</quiz>"
        let (text, quiz) = QuizService.extract(from: reply)
        #expect(text == "Sure thing!")
        #expect(quiz == nil)
    }

    @Test("选项数不为 4 视为无效，放弃 quiz")
    func extractInvalidOptionCount() {
        let reply = """
        Hi<quiz>{"question":"Q","options":["A","B","C"],"answer":0,"explanation_zh":"x"}</quiz>
        """
        let (_, quiz) = QuizService.extract(from: reply)
        #expect(quiz == nil)
    }

    @Test("answer 越界视为无效")
    func extractAnswerOutOfRange() {
        let reply = """
        Hi<quiz>{"question":"Q","options":["A","B","C","D"],"answer":9,"explanation_zh":"x"}</quiz>
        """
        let (_, quiz) = QuizService.extract(from: reply)
        #expect(quiz == nil)
    }

    @Test("编解码往返")
    func encodeDecodeRoundTrip() {
        let quiz = Quiz(question: "Q", options: ["A", "B", "C", "D"], answer: 2, explanationZh: "解析")
        let json = QuizService.encode(quiz)
        #expect(json != nil)
        let decoded = QuizService.decode(fromJSON: json)
        #expect(decoded == quiz)
        #expect(QuizService.decode(fromJSON: nil) == nil)
    }

    @Test("作答反馈：对/错文案与判分")
    func feedback() {
        let quiz = Quiz(question: "Q", options: ["A", "B", "C", "D"], answer: 1, explanationZh: "因为 B 对")
        let right = QuizService.feedback(quiz: quiz, chosenIndex: 1)
        #expect(right.correct)
        #expect(right.message.contains("答对"))
        let wrong = QuizService.feedback(quiz: quiz, chosenIndex: 0)
        #expect(!wrong.correct)
        #expect(wrong.message.contains("B")) // 提示正确项内容
        #expect(wrong.message.contains("因为 B 对"))
    }

    @Test("选项字母映射")
    func optionLabels() {
        #expect(QuizService.optionLabel(0) == "A")
        #expect(QuizService.optionLabel(3) == "D")
        #expect(QuizService.optionLabel(9) == "?")
    }

    @Test("出题指令包裹格式提示存在")
    func promptInstruction() {
        #expect(QuizService.promptInstruction.contains("<quiz>"))
        #expect(QuizService.promptInstruction.contains("Exactly 4 options"))
    }
}

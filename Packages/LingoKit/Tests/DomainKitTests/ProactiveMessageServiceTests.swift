import Foundation
import Testing
@testable import DomainKit
import PersistenceKit

@Suite("角色主动消息")
struct ProactiveMessageServiceTests {
    @Test("模型输出会整理为一条自然消息")
    func normalizesGeneratedMessage() async {
        let llm = MockLLMProvider { _ in
            "  \"Found an old photo today. What photos do you like?\"  \n"
        }
        let service = ProactiveMessageService(llm: llm)

        let message = await service.generate(
            for: character(),
            learner: learner(),
            occasion: .introduction
        )

        #expect(message == "Found an old photo today. What photos do you like?")
    }

    @Test("消息空白通过一次扫描统一归一化")
    func normalizesMixedWhitespace() {
        #expect(
            ProactiveMessageService.normalized(
                "  \"Hello,\tthere!\n\nWhat   made you smile today?\"  "
            ) == "Hello, there! What made you smile today?"
        )
    }

    @Test("明显过长或超过两句的模型输出会触发重写")
    func rejectsVerboseGeneratedMessage() {
        #expect(ProactiveMessageService.normalized(
            "Afternoon, Xiaoyu. I spent an hour shelving books and arguing with a customer about whether Orwell is overrated. Reckon that is a debate you would have an opinion on?"
        ) == nil)
        #expect(ProactiveMessageService.normalized(
            "Saw something funny today. What made you laugh?"
        ) != nil)
    }

    @Test("首次格式不合格时会让模型重写而不是立即使用兜底")
    func retriesInvalidModelOutput() async {
        let responses = ProactiveResponseSequence([
            "This is far too long. It keeps going. It adds a third sentence.",
            "Found a quiet cafe today. What's your ideal study spot?",
        ])
        let llm = MockLLMProvider { _ in
            await responses.next()
        }
        let service = ProactiveMessageService(llm: llm, variationIndex: { 2 })

        let message = await service.generate(
            for: character(),
            learner: learner(),
            occasion: .introduction
        )

        #expect(message == "Found a quiet cafe today. What's your ideal study spot?")
        let callCount = await responses.callCount
        #expect(callCount == 2)
    }

    @Test("模型失败时不写入固定兜底并保留稍后重试机会")
    func skipsMessageWhenModelFails() async {
        let llm = MockLLMProvider { _ in
            throw NSError(domain: "test", code: 1)
        }
        let service = ProactiveMessageService(llm: llm, variationIndex: { 0 })

        let message = await service.generate(
            for: character(),
            learner: learner(),
            occasion: .introduction
        )

        #expect(message == nil)
    }

    @Test("主动问候提示词包含角色身份、英语水平与去重上下文")
    func promptCarriesContext() {
        let recent = MessageDTO(
            id: UUID(),
            role: .user,
            kind: .text,
            text: "I went hiking yesterday.",
            orderIndex: 0
        )

        let prompt = ProactiveMessageService.prompt(
            character: character(),
            learner: learner(),
            occasion: .checkIn,
            recentMessages: [recent]
        )

        #expect(prompt.contains("street photographer"))
        #expect(prompt.contains("I went hiking yesterday."))
        #expect(prompt.contains("Chinese English learner"))
        #expect(prompt.contains("study abroad"))
        #expect(prompt.contains("university learner"))
        #expect(prompt.contains("Do not guilt"))
        #expect(prompt.contains("comprehension ceiling"))
        #expect(prompt.contains("6-14 words total"))
    }

    @Test("首次联系明确延续已约好的旅行伙伴关系")
    func introductionPromptPreservesStoryPremise() {
        let prompt = ProactiveMessageService.prompt(
            character: character(),
            learner: learner(),
            occasion: .introduction,
            recentMessages: []
        )

        #expect(prompt.contains("already been introduced"))
        #expect(prompt.contains("expected the two of you to be in touch"))
        #expect(prompt.contains("Never act shocked"))
    }

    @Test("与既定关系矛盾的惊讶开场会被重写")
    func rejectsContradictoryIntroduction() async {
        let responses = ProactiveResponseSequence([
            "You actually texted me. Am I dreaming or is my phone broken, mate?",
            "Welcome to town, mate. How was your trip?",
        ])
        let service = ProactiveMessageService(
            llm: MockLLMProvider { _ in await responses.next() },
            variationIndex: { 3 }
        )

        let message = await service.generate(
            for: character(),
            learner: learner(),
            occasion: .introduction
        )

        #expect(message == "Welcome to town, mate. How was your trip?")
        #expect(await responses.callCount == 2)
    }

    private func learner() -> LearnerContext {
        LearnerContext(
            nickname: "小雨",
            difficulty: .senior2,
            goal: .studyAbroad,
            studyStage: .university
        )
    }

    private func character() -> CharacterDTO {
        CharacterDTO(
            id: UUID(),
            card: CharacterCard(
                name: "Morgan Lee",
                age: 28,
                gender: .other,
                nationality: "Canadian",
                regionID: "toronto",
                occupation: "street photographer",
                hobbies: ["film photography"],
                appearance: "casual",
                personality: "curious and observant"
            ),
            difficultyLevel: .junior3,
            isMainCharacter: false,
            isFriend: true,
            metAt: .now
        )
    }
}

private actor ProactiveResponseSequence {
    private var responses: [String]
    private(set) var callCount = 0

    init(_ responses: [String]) {
        self.responses = responses
    }

    func next() -> String {
        callCount += 1
        guard !responses.isEmpty else { return "" }
        return responses.removeFirst()
    }
}

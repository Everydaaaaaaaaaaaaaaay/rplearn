import Foundation
import Testing
@testable import DomainKit
import PersistenceKit

@Suite("角色主动消息")
struct ProactiveMessageServiceTests {
    @Test("模型输出会整理为一条自然消息")
    func normalizesGeneratedMessage() async {
        let llm = MockLLMProvider { _ in
            "  \"I found an old photo at the shop today. What kind of photos do you like taking?\"  \n"
        }
        let service = ProactiveMessageService(llm: llm)

        let message = await service.generate(
            for: character(),
            learner: learner(),
            occasion: .introduction
        )

        #expect(message == "I found an old photo at the shop today. What kind of photos do you like taking?")
    }

    @Test("消息空白通过一次扫描统一归一化")
    func normalizesMixedWhitespace() {
        #expect(
            ProactiveMessageService.normalized(
                "  \"Hello,\tthere!\n\nWhat   made you smile today?\"  "
            ) == "Hello, there! What made you smile today?"
        )
    }

    @Test("过长或超过两句的模型输出会交给短消息兜底")
    func rejectsVerboseGeneratedMessage() {
        #expect(ProactiveMessageService.normalized(
            "Afternoon, Xiaoyu. I spent an hour shelving books and arguing with a customer about whether Orwell is overrated. Reckon that is a debate you would have an opinion on?"
        ) == nil)
        #expect(ProactiveMessageService.normalized(
            "I saw something funny at work today and thought of you. What made you laugh today?"
        ) != nil)
    }

    @Test("模型失败时仍返回符合身份字段的英文话题")
    func fallsBackWithoutCharacterHardcoding() async {
        let llm = MockLLMProvider { _ in
            throw NSError(domain: "test", code: 1)
        }
        let service = ProactiveMessageService(llm: llm)

        let message = await service.generate(
            for: character(),
            learner: learner(),
            occasion: .introduction
        )

        #expect(message.contains("street photographer"))
        #expect(message.hasSuffix("?"))
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
        #expect(prompt.contains("8-20 words total"))
    }

    @Test("初学者的离线兜底同样保持短句与选择式问题")
    func beginnerFallbackIsScaffolded() async {
        let llm = MockLLMProvider { _ in
            throw NSError(domain: "test", code: 1)
        }
        let service = ProactiveMessageService(llm: llm)
        let message = await service.generate(
            for: character(),
            learner: LearnerContext(difficulty: .primary2, goal: .travel),
            occasion: .introduction
        )

        #expect(message == "Hi! Let’s take a trip. Train or plane?")
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

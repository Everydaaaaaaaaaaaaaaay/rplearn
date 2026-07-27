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

        let message = await service.generate(for: character(), occasion: .introduction)

        #expect(message == "I found an old photo at the shop today. What kind of photos do you like taking?")
    }

    @Test("模型失败时仍返回符合身份字段的英文话题")
    func fallsBackWithoutCharacterHardcoding() async {
        let llm = MockLLMProvider { _ in
            throw NSError(domain: "test", code: 1)
        }
        let service = ProactiveMessageService(llm: llm)

        let message = await service.generate(for: character(), occasion: .introduction)

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
            occasion: .checkIn,
            recentMessages: [recent]
        )

        #expect(prompt.contains("street photographer"))
        #expect(prompt.contains("I went hiking yesterday."))
        #expect(prompt.contains("Chinese English learner"))
        #expect(prompt.contains("Do not guilt"))
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

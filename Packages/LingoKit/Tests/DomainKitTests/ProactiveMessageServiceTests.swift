import Foundation
import LLMKit
import Testing
@testable import DomainKit
import PersistenceKit

@Suite("角色主动消息")
struct ProactiveMessageServiceTests {
    @Test("模型输出会整理为一条自然消息")
    func normalizesGeneratedMessage() async {
        let recorder = ProactiveRequestRecorder()
        let llm = MockLLMProvider { request in
            await recorder.record(request)
            return "  \"Found an old photo today. What photos do you like?\"  \n"
        }
        let service = ProactiveMessageService(llm: llm)

        let message = await service.generate(
            for: character(),
            learner: learner(),
            occasion: .introduction
        )

        #expect(message == "Found an old photo today. What photos do you like?")
        #expect(await recorder.tasks == [.proactiveMessage])
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
        #expect(prompt.contains("中国英语学习者"))
        #expect(prompt.contains("海外留学"))
        #expect(prompt.contains("大学生"))
        #expect(prompt.contains("不要使朋友内疚"))
        #expect(prompt.contains("理解难度的上限"))
        #expect(prompt.contains("总计 6—14 个英语词"))
    }

    @Test("主动消息按投递时刻写作且不叠加未回答的问题")
    func promptUsesDeliveryTimeAndProtectsUnansweredTurn() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let delivery = try #require(
            utc.date(from: DateComponents(
                year: 2026,
                month: 9,
                day: 6,
                hour: 14
            ))
        )
        let previous = MessageDTO(
            id: UUID(),
            role: .assistant,
            kind: .text,
            text: "Did your presentation go well?",
            orderIndex: 0,
            createdAt: delivery.addingTimeInterval(-48 * 60 * 60)
        )

        let prompt = ProactiveMessageService.prompt(
            character: character(),
            learner: learner(),
            occasion: .checkIn,
            recentMessages: [previous],
            deliveryDate: delivery
        )

        #expect(prompt.contains("## 可信的当前时间语境"))
        #expect(prompt.contains("2026-09-06"))
        #expect(prompt.contains("上一条消息还未得到回复"))
        #expect(prompt.contains("不要重复或再叠加问题"))
        #expect(prompt.contains("保留事实、计划状态、情绪连续性"))
    }

    @Test("首次联系明确延续已约好的旅行伙伴关系")
    func introductionPromptPreservesStoryPremise() {
        let prompt = ProactiveMessageService.prompt(
            character: character(),
            learner: learner(),
            occasion: .introduction,
            recentMessages: []
        )

        #expect(prompt.contains("已经互相介绍"))
        #expect(prompt.contains("预期双方会联系"))
        #expect(prompt.contains("不要因对方联系你而惊讶"))
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

private actor ProactiveRequestRecorder {
    private(set) var tasks: [LLMTask] = []

    func record(_ request: LLMRequest) {
        tasks.append(request.task)
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

import Foundation
import LLMKit
import PersistenceKit
@testable import LearningFeature
import Testing

@Suite("Practice companion messages")
struct PracticeCompanionMessageTests {
    private func card() -> CharacterCard {
        .init(name: "Test companion", age: 30, gender: .male, nationality: "British", regionID: "london",
              occupation: "gardener", hobbies: ["reading"], appearance: "", personality: "温和，话少，有干幽默。",
              speechStyle: "简短平实，偶尔冷笑话。")
    }
    private let lines = PracticeCompanionLines(
        opening: ["慢慢来，我在这里。", "先读读看。", "留几分钟给自己。", "准备好了就开始吧。", "按你的节奏来。"],
        closing: ["这一组做完了。", "辛苦了，休息一下吧。", "先松一口气。", "今天先到这里。", "我们下次接着来。"])

    @Test("Exactly five distinct short one-or-two-sentence lines per moment")
    func validation() {
        #expect(lines.isValid)
        #expect(!PracticeCompanionLines(opening: Array(repeating: "重复。", count: 5), closing: lines.closing).isValid)
        #expect(!PracticeCompanionLines(opening: ["一。二。三。"] + Array(lines.opening.dropFirst()), closing: lines.closing).isValid)
        #expect(!PracticeCompanionLines(opening: [String(repeating: "长", count: 53)] + Array(lines.opening.dropFirst()), closing: lines.closing).isValid)
        #expect(!PracticeCompanionLines(opening: ["两行\n文字。"] + Array(lines.opening.dropFirst()), closing: lines.closing).isValid)
        for name in ["Oliver Bennett", "Ruby Walker", "Marcus Rivera"] {
            var persona = card(); persona.name = name
            #expect(PracticeCompanionLines.seed(for: persona)?.isValid == true)
        }
    }

    @Test("Validated AI lines persist by persona and regenerate when the personality changes")
    func generationAndCache() async throws {
        let counter = CompanionCallCounter()
        let payload = String(decoding: try JSONEncoder().encode(lines), as: UTF8.self)
        let llm = MockLLMProvider { request in
            await counter.record()
            #expect(request.task == .proactiveMessage)
            #expect(request.messages[0].content.contains("gardener"))
            #expect(request.system?.contains("各有5条") == true)
            return payload
        }
        let suite = "PracticeCompanionTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let service = PracticeCompanionMessageService(llm: llm, suiteName: suite)
        async let first = service.lines(for: card())
        async let second = service.lines(for: card())
        #expect(await first == lines)
        #expect(await second == lines)
        #expect(await counter.count == 1)
        let reopened = PracticeCompanionMessageService(llm: llm, suiteName: suite)
        #expect(await reopened.lines(for: card()) == lines)
        #expect(await counter.count == 1)
        var changed = card(); changed.personality = "热情开朗，行动果断。"
        #expect(await reopened.lines(for: changed) == lines)
        #expect(await counter.count == 2)
    }

    @Test("Invalid output is not persisted and can be retried on the next practice")
    func invalidOutput() async {
        let counter = CompanionCallCounter()
        let llm = MockLLMProvider { _ in await counter.record(); return "{\"opening\":[\"过长或缺少台词\"],\"closing\":[]}" }
        let suite = "PracticeCompanionTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let service = PracticeCompanionMessageService(llm: llm, suiteName: suite)
        #expect(await service.lines(for: card()) == nil)
        #expect(await service.lines(for: card()) == nil)
        #expect(await counter.count == 2)
    }

    @Test("Task labels reflect actual question kinds without titles or repeated metadata")
    func taskTypes() {
        #expect(PracticePreviewFixtures.tasks.map(\.kindTitle) == ["阅读理解", "完形填空", "七选五 · 语法填空"])
        #expect(PracticeTimeEstimate.label(8) == "5–8")
        #expect(PracticeTimeEstimate.label(0) == "1–2")
    }
}

private actor CompanionCallCounter {
    var count = 0
    func record() { count += 1 }
}

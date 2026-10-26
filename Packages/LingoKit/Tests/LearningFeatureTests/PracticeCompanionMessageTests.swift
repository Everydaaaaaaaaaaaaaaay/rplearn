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
        opening: ["Take your time. I'm right here.", "Let's turn the page.", "A quiet moment, just for you.", "Ready when you are.", "Let's go at your pace."],
        closing: ["That's a wrap.", "Time for a little break.", "Take a breath.", "Let's leave it here for today.", "Catch you next time."])

    @Test("Exactly five distinct short one-or-two-sentence lines per moment")
    func validation() {
        #expect(lines.isValid)
        #expect(!PracticeCompanionLines(opening: Array(repeating: "Same line.", count: 5), closing: lines.closing).isValid)
        #expect(!PracticeCompanionLines(opening: ["One. Two. Three."] + Array(lines.opening.dropFirst()), closing: lines.closing).isValid)
        #expect(!PracticeCompanionLines(opening: [String(repeating: "a", count: 101)] + Array(lines.opening.dropFirst()), closing: lines.closing).isValid)
        #expect(!PracticeCompanionLines(opening: ["Two\nlines."] + Array(lines.opening.dropFirst()), closing: lines.closing).isValid)
        #expect(!PracticeCompanionLines(opening: ["Take your time，慢慢来。"] + Array(lines.opening.dropFirst()), closing: lines.closing).isValid)
        #expect(!PracticeCompanionLines(opening: ["准备好了就开始。"] + Array(lines.opening.dropFirst()), closing: lines.closing).isValid)
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
            #expect(request.system?.contains("所有台词必须完全使用英语") == true)
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

    @Test("Old Chinese cache entries cannot replace English bookend messages")
    func chineseCacheIsRejected() async throws {
        let suite = "PracticeCompanionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = PracticeCompanionMessageService.cacheKey(for: card())
        let legacyKey = key.replacingOccurrences(of: "practice.companion.v2.en.", with: "practice.companion.v1.")
        let chinese = PracticeCompanionLines(opening: ["慢慢来。", "先看看。", "准备开始。", "一起试试。", "翻开这一页。"],
                                             closing: ["歇一会儿。", "今天到这里。", "结束了。", "下次再来。", "喝口水吧。"])
        let oldData = try JSONEncoder().encode(chinese)
        defaults.set(oldData, forKey: legacyKey)
        defaults.set(oldData, forKey: key)
        let counter = CompanionCallCounter()
        let payload = String(decoding: try JSONEncoder().encode(lines), as: UTF8.self)
        let service = PracticeCompanionMessageService(llm: MockLLMProvider { _ in
            await counter.record(); return payload
        }, suiteName: suite)
        #expect(await service.lines(for: card()) == lines)
        #expect(await service.lines(for: card()) == lines)
        #expect(await counter.count == 1)
        #expect(defaults.data(forKey: legacyKey) == oldData)
        #expect(try JSONDecoder().decode(PracticeCompanionLines.self, from: #require(defaults.data(forKey: key))) == lines)
    }

    @Test("Invalid output is not persisted and can be retried on the next practice")
    func invalidOutput() async throws {
        let counter = CompanionCallCounter()
        let chinese = PracticeCompanionLines(opening: ["慢慢来。", "先看看。", "准备开始。", "一起试试。", "翻开这一页。"],
                                             closing: ["歇一会儿。", "今天到这里。", "结束了。", "下次再来。", "喝口水吧。"])
        let payload = String(decoding: try JSONEncoder().encode(chinese), as: UTF8.self)
        let llm = MockLLMProvider { _ in await counter.record(); return payload }
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

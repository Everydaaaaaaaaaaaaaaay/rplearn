import CoreKit
import Foundation
import LLMKit
import Testing
@testable import DomainKit
@testable import PersistenceKit

/// Local fixture export only: this test never contacts a model provider.
@Suite("Prompt cache fixture")
struct PromptCacheEvaluationTests {
    @Test("导出固定对话的缓存测试输入，不调用模型")
    func exportFixture() throws {
        let card = CharacterCard(name: "Oliver Bennett", age: 24, gender: .male,
            nationality: "British", regionID: "london", occupation: "bookseller",
            hobbies: ["football", "indie music"], appearance: "messy brown hair",
            personality: "dry humour, warm underneath", speechStyle: "says mate a lot", background: "grew up in Kent")
        let lines = [
            "Hi Oliver, I'm looking for a book to read on the train.",
            "I'd prefer a short mystery. Nothing too grim, though.",
            "That sounds good. Is it easy to follow in English?",
            "I'll give it a try. What do you like about it?",
        ]
        let replies = ["A train book? Something short, or a proper doorstop?", "A cosy mystery might do the trick", "Fairly clear language, and short chapters help"]
        var history: [MessageDTO] = []
        var bodies: [[String: Any]] = []
        let start = Date(timeIntervalSince1970: 1_789_099_200)
        for (index, line) in lines.enumerated() {
            let date = start.addingTimeInterval(Double(index * 75))
            history.append(MessageDTO(id: UUID(), role: .user, kind: .text, text: line,
                orderIndex: history.count, createdAt: date))
            let request = PromptBuilder.roleplayRequest(card: card, learner: .fallback(difficulty: .junior3),
                history: history, memorySections: ["[Long-term things you know about your friend]\n- The friend likes short books and travels by train."], currentDate: date)
            let messages = [["role": "system", "content": request.system ?? ""]] + request.messages.map {
                ["role": $0.role.rawValue, "content": $0.content]
            }
            bodies.append(["messages": messages, "max_tokens": request.maxTokens])
            if index < replies.count {
                history.append(MessageDTO(id: UUID(), role: .assistant, kind: .text, text: replies[index],
                    orderIndex: history.count, createdAt: date.addingTimeInterval(5)))
            }
        }
        let systems = bodies.compactMap { ($0["messages"] as? [[String: String]])?.first?["content"] }
        let fixedPrefixes = systems.map { $0.components(separatedBy: "## 可信的当前时间语境")[0] }
        #expect(Set(fixedPrefixes).count == 1)
        // 中文与英文的字符/token 比不同，按项目估算器检查缓存前缀规模。
        #expect(TokenEstimator.estimate(fixedPrefixes[0]) > 1_024)
        #expect(Set(systems).count == 4)
        let output = URL(fileURLWithPath: "/tmp/lingotrip-cache-fixture.json")
        try JSONSerialization.data(withJSONObject: bodies, options: [.sortedKeys, .prettyPrinted]).write(to: output)
        #expect(bodies.count == 4)
        print("Cache fixture exported: \(output.path)")
    }
}

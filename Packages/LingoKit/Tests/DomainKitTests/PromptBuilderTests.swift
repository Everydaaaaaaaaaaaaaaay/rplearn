import Foundation
import Testing
@testable import DomainKit
@testable import PersistenceKit

@Suite("PromptBuilder")
struct PromptBuilderTests {
    private let card = CharacterCard(
        name: "Oliver Bennett",
        age: 24,
        gender: .male,
        nationality: "British",
        regionID: "london",
        occupation: "bookseller",
        hobbies: ["football", "indie music"],
        appearance: "messy brown hair",
        personality: "dry humour, warm underneath",
        speechStyle: "says mate a lot",
        background: "grew up in Kent"
    )

    @Test("system prompt 锁定关键结构（snapshot 式断言）")
    func systemPromptStructure() {
        let prompt = PromptBuilder.roleplaySystemPrompt(card: card, difficulty: .junior3)

        // 角色卡信息全部渲染
        #expect(prompt.contains("Oliver Bennett"))
        #expect(prompt.contains("24-year-old British man"))
        #expect(prompt.contains("bookseller"))
        #expect(prompt.contains("football, indie music"))
        #expect(prompt.contains("says mate a lot"))
        #expect(prompt.contains("grew up in Kent"))

        // 固定指令段落
        #expect(prompt.contains("## Roleplay rules"))
        #expect(prompt.contains("Never mention that you are an AI"))
        #expect(prompt.contains("## Texting style"))
        #expect(prompt.contains("skip the final punctuation"))
        #expect(prompt.contains("## Language level"))
        #expect(prompt.contains("## Gentle correction"))
        #expect(prompt.contains("at most one correction per message"))
    }

    @Test("各学制等级都有对应语言约束", arguments: DifficultyLevel.allCases)
    func languageGuidancePerLevel(level: DifficultyLevel) {
        let guidance = PromptBuilder.languageGuidance(for: level)
        #expect(!guidance.isEmpty)
        let prompt = PromptBuilder.roleplaySystemPrompt(card: card, difficulty: level)
        #expect(prompt.contains(guidance))
    }

    @Test("记忆段落拼在末尾")
    func memorySections() {
        let prompt = PromptBuilder.roleplaySystemPrompt(
            card: card,
            difficulty: .senior1,
            memorySections: ["[Things you remember]\n- user likes cats"]
        )
        #expect(prompt.hasSuffix("- user likes cats"))
    }

    @Test("历史映射：过滤 coach、按序、窗口截断")
    func chatMessagesMapping() {
        var history: [MessageDTO] = []
        for index in 0..<30 {
            history.append(
                MessageDTO(
                    id: UUID(),
                    role: index % 3 == 2 ? .coach : (index % 2 == 0 ? .user : .assistant),
                    kind: .text,
                    text: "m\(index)",
                    orderIndex: index
                )
            )
        }
        let mapped = PromptBuilder.chatMessages(history: history.shuffled(), rawWindow: 10)
        #expect(mapped.count == 10)
        // 不含 coach 消息，且保持相对顺序
        let texts = mapped.map(\.content)
        let indices = texts.compactMap { Int($0.dropFirst()) }
        #expect(indices == indices.sorted())
        for index in indices {
            #expect(index % 3 != 2)
        }
    }

    @Test("角色扮演请求参数符合任务矩阵")
    func roleplayRequestParameters() {
        let request = PromptBuilder.roleplayRequest(card: card, difficulty: .junior3, history: [])
        #expect(request.tier == .balanced)
        #expect(request.maxTokens == 512)
        #expect(request.temperature == 0.9)
        #expect(request.responseFormat == .text)
    }

    @Test("出题回合：附加出题指令并放宽 maxTokens")
    func quizRequestedAppendsInstruction() {
        let plain = PromptBuilder.roleplaySystemPrompt(card: card, difficulty: .junior3)
        #expect(!plain.contains("Optional pop quiz"))

        let withQuiz = PromptBuilder.roleplaySystemPrompt(card: card, difficulty: .junior3, quizRequested: true)
        #expect(withQuiz.contains("## Optional pop quiz"))
        #expect(withQuiz.contains("<quiz>"))

        let request = PromptBuilder.roleplayRequest(card: card, difficulty: .junior3, history: [], quizRequested: true)
        #expect(request.system?.contains("Optional pop quiz") == true)
        #expect(request.maxTokens == 900)
    }
}

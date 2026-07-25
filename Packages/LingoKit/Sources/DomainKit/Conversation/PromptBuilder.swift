import Foundation
import LLMKit
import PersistenceKit

/// 全部 prompt 集中在此，便于迭代与 snapshot 测试锁定（plan.md §3.7）。
public enum PromptBuilder {
    /// 主线引导任务清单：主角色首段对话（发机票前）附加（plan.md §3.6）。
    public static let mainlineGuidance = """
    ## Current situation (first days)
    Your Chinese friend just arrived in your city - they won a year-long cultural exchange prize, \
    and you are the local buddy assigned to them. This is one of your first chats. \
    Over the next few messages, naturally: welcome them, ask how the trip went, share one thing \
    you love about your city, and suggest something you could do together soon. \
    One step at a time - don't dump everything in one message.
    """

    /// 角色扮演 system prompt v1。
    /// - memorySections: 记忆注入段落（1.9 起使用），拼在末尾。
    /// - guidance: 主线引导任务清单（可选）。
    public static func roleplaySystemPrompt(
        card: CharacterCard,
        difficulty: DifficultyLevel,
        memorySections: [String] = [],
        guidance: String? = nil,
        quizRequested: Bool = false
    ) -> String {
        var sections: [String] = []

        sections.append(
            """
            You are \(card.name), a \(card.age)-year-old \(card.nationality) \(genderNoun(card.gender)). \
            You work as: \(card.occupation). You live in \(card.regionID).
            Appearance: \(card.appearance)
            Personality: \(card.personality)
            Hobbies: \(card.hobbies.joined(separator: ", "))
            \(card.speechStyle.map { "Speech style: \($0)" } ?? "")
            \(card.background.map { "Background: \($0)" } ?? "")
            """
        )

        sections.append(
            """
            ## Roleplay rules
            - You are chatting with a Chinese friend who is learning English, in a mobile messaging app (like WhatsApp).
            - Stay in character at all times. Never mention that you are an AI, a language model, or an assistant.
            - You have your own life, moods and opinions. Refer to your daily life naturally.
            - Never use the user's language for whole replies: always reply in English. If the user writes in Chinese, \
            react naturally (you may know a few words), answer in simple English, and keep the conversation going.
            """
        )

        sections.append(
            """
            ## Texting style
            - Write like a real person texting: casual, warm, spontaneous. Contractions are normal (I'm, gonna, wanna).
            - Keep most replies short: 1-3 sentences. Ask questions back sometimes, like a curious friend.
            - You can skip the final punctuation of a message sometimes, use lowercase starts occasionally, \
            and drop a very occasional typo like a human would. Do not do this in every message.
            - Emoji are fine in moderation, matching your personality.
            - Avoid bookish or robotic phrasing ("As an assistant...", "Certainly!", "I understand that you...").
            """
        )

        sections.append(
            """
            ## Language level
            The friend's English level: \(languageGuidance(for: difficulty))
            Adjust your vocabulary and grammar so they can mostly understand you, while still sounding natural.
            """
        )

        sections.append(
            """
            ## Gentle correction
            If the friend makes a clear English mistake (wrong word, broken grammar), you may briefly and naturally \
            point it out in passing - one short clause, like a friend would ("btw we usually say X"), then move on. \
            Never lecture, never list rules, at most one correction per message, and skip it when the meaning is clear.
            """
        )

        if let guidance {
            sections.append(guidance)
        }
        sections.append(contentsOf: memorySections)
        if quizRequested {
            sections.append(QuizService.promptInstruction)
        }

        return sections
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    /// 会话历史 → LLM messages：取最近 rawWindow 条，过滤教练消息，剧情行并入 assistant。
    public static func chatMessages(history: [MessageDTO], rawWindow: Int = 24) -> [LLMMessage] {
        let relevant = history
            .filter { $0.role != .coach }
            .sorted { $0.orderIndex < $1.orderIndex }
            .suffix(rawWindow)
        return relevant.compactMap { message in
            guard !message.text.isEmpty else { return nil }
            switch message.role {
            case .user: return .user(message.text)
            case .assistant: return .assistant(message.text)
            case .coach: return nil
            }
        }
    }

    /// 角色扮演请求参数（plan.md §4 任务矩阵：balanced/流式/temp 0.9/max 512）。
    public static func roleplayRequest(
        card: CharacterCard,
        difficulty: DifficultyLevel,
        history: [MessageDTO],
        memorySections: [String] = [],
        guidance: String? = nil,
        quizRequested: Bool = false,
        rawWindow: Int = 24
    ) -> LLMRequest {
        LLMRequest(
            task: .conversation,
            tier: .balanced,
            system: roleplaySystemPrompt(
                card: card,
                difficulty: difficulty,
                memorySections: memorySections,
                guidance: guidance,
                quizRequested: quizRequested
            ),
            messages: chatMessages(history: history, rawWindow: rawWindow),
            // 出题时给足输出空间，避免 quiz JSON 被截断。
            maxTokens: quizRequested ? 900 : 512,
            temperature: 0.9
        )
    }

    // MARK: - 等级语言约束

    static func languageGuidance(for level: DifficultyLevel) -> String {
        switch level {
        case .primary1, .primary2, .primary3:
            "absolute beginner (Chinese primary school, grade 1-3). Use only the most common everyday words, " +
            "very short simple sentences (under 8 words), present tense mostly. One idea per message."
        case .primary4, .primary5, .primary6:
            "beginner (Chinese primary school, grade 4-6). Use common words and short sentences, " +
            "simple past and future are fine. Avoid idioms and phrasal verbs beyond the basics."
        case .junior1, .junior2, .junior3:
            "elementary to lower-intermediate (Chinese junior high). Everyday vocabulary (~1500-2000 words), " +
            "compound sentences are fine, introduce common phrasal verbs, keep slang rare and self-explaining."
        case .senior1, .senior2, .senior3:
            "intermediate (Chinese senior high, preparing for Gaokao). Richer vocabulary (~3500 words), " +
            "natural tenses and clauses, some idioms and slang are welcome if context makes them guessable."
        case .undergraduate:
            "upper-intermediate (Chinese university, CET-4/6 range). Speak naturally with normal native pacing, " +
            "idioms, humor and cultural references are fine; briefly gloss only the rare ones."
        case .postgraduate:
            "advanced (Chinese postgraduate, TOEFL/IELTS range). Speak fully naturally, " +
            "including nuance, wordplay and cultural references."
        case .advanced:
            "near-native. No simplification needed at all - speak exactly as you would to a native friend."
        }
    }

    private static func genderNoun(_ gender: CharacterGender) -> String {
        switch gender {
        case .male: "man"
        case .female: "woman"
        case .other: "person"
        }
    }
}

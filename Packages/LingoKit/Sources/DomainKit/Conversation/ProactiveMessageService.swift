import CoreKit
import Foundation
import LLMKit
import PersistenceKit

/// 生成角色主动发起的话题。这里只负责文案，发送时机由应用层统一编排。
public struct ProactiveMessageService: Sendable {
    private static let maximumWordsPerMessage = 18

    public enum Occasion: Sendable, Equatable {
        /// 刚成为好友时的第一条消息。
        case introduction
        /// 一段时间没有交流后的自然问候。
        case checkIn
    }

    private let llm: any LLMClient
    private let variationIndex: @Sendable () -> Int

    public init(
        llm: any LLMClient,
        variationIndex: @escaping @Sendable () -> Int = { Int.random(in: 0..<10_000) }
    ) {
        self.llm = llm
        self.variationIndex = variationIndex
    }

    /// 仅返回通过校验且不重复的模型消息；生成失败时留给编排层稍后重试。
    public func generate(
        for character: CharacterDTO,
        learner: LearnerContext,
        occasion: Occasion,
        recentMessages: [MessageDTO] = [],
        scheduledFor deliveryDate: Date = .now
    ) async -> String? {
        let variation = variationIndex()
        let recentAssistantTexts = recentMessages
            .filter { $0.role == .assistant }
            .suffix(8)
            .map(\.text)

        for attempt in 0..<2 {
            let repairInstruction = attempt == 0
                ? ""
                : "\nThe previous draft was invalid or repetitive. Rewrite it more briefly and with a different opening."
            let request = LLMRequest(
                task: .conversation,
                tier: .fast,
                system: Self.prompt(
                    character: character,
                    learner: learner,
                    occasion: occasion,
                    recentMessages: recentMessages,
                    variationIndex: variation + attempt,
                    deliveryDate: deliveryDate
                ) + repairInstruction,
                messages: [.user("Write the message now.")],
                maxTokens: 72,
                temperature: 0.8
            )

            let output: String
            do {
                output = try await llm.complete(request)
            } catch {
                // LLMRouter 已经对网络和限流错误重试；此处不再重复轰炸服务端。
                Log.llm.warning("主动消息生成失败，本轮不写入并保留稍后重试机会：\(error)")
                return nil
            }
            guard let message = Self.normalized(output),
                  Self.isContextuallyValid(message, for: occasion)
            else {
                Log.llm.warning("主动开场第 \(attempt + 1) 次输出未通过格式或情境校验")
                continue
            }
            guard !RoleplayReplyDiversityPolicy.isTooSimilar(
                message,
                to: recentAssistantTexts
            ) else {
                Log.llm.warning("主动开场第 \(attempt + 1) 次输出与近期消息重复")
                continue
            }
            return message
        }
        Log.llm.warning("主动消息连续两次未通过校验，本轮不写入并保留稍后重试机会")
        return nil
    }

    static func prompt(
        character: CharacterDTO,
        learner: LearnerContext,
        occasion: Occasion,
        recentMessages: [MessageDTO],
        variationIndex: Int = 0,
        deliveryDate: Date = .now
    ) -> String {
        let card = character.card
        let hasUnansweredCharacterMessage = recentMessages
            .last(where: { $0.role != .coach && !$0.text.isEmpty })?
            .role == .assistant
        let situation = switch occasion {
        case .introduction:
            """
            The two of you have already been introduced and agreed to be travel friends. You knew this \
            person was coming to your city and expected the two of you to be in touch. Send the first \
            message yourself as a planned, friendly welcome, then open a topic that is easy and interesting \
            for this person to answer. Never act shocked that they contacted you, question whether the \
            contact is real, or imply that your phone must be broken.
            """
        case .checkIn:
            """
            You are sending one low-pressure check-in after quiet time. Mention a small, believable detail that fits \
            your life and the scheduled delivery time. Do not claim live weather, news or another external fact. Do \
            not guilt the friend, mention how long they have been silent, demand a reply, or act as if you have been \
            waiting motionless. Preserve unresolved plans and feelings instead of contradicting or silently completing them.
            """
        }
        let recent = recentMessages
            .suffix(8)
            .map { message in
                let speaker = message.role == .user ? "Friend" : card.name
                let timestamp = RoleplayTemporalContext.transcriptTimestamp(
                    message.createdAt,
                    regionID: card.regionID
                )
                return "[\(timestamp)] \(speaker): \(message.text)"
            }
            .joined(separator: "\n")
        let endingInstruction = hasUnansweredCharacterMessage && occasion == .checkIn
            ? "Your last message is still unanswered. Do not repeat it or stack another question; share one easy, self-contained thought that does not require a reply."
            : "End with one approachable question."

        return """
        You are \(card.name), a \(card.age)-year-old \(card.nationality) person living in \(card.regionID).
        Occupation: \(card.occupation)
        Hobbies: \(card.hobbies.joined(separator: ", "))
        Personality: \(card.personality)
        \(card.speechStyle.map { "Speech style: \($0)" } ?? "")
        \(card.background.map { "Background: \($0)" } ?? "")
        \(card.personaVoice.map { voice in
            "Values: \(voice.values.joined(separator: ", "))\nConversational habits: \(voice.conversationalHabits.joined(separator: ", "))\nVoice examples (do not copy): \(voice.anchorLines.prefix(4).joined(separator: " | "))"
        } ?? "")

        \(RoleplayTemporalContext.currentSituation(regionID: card.regionID, at: deliveryDate))

        \(situation)

        The friend's preferred name is \(learner.nickname ?? "not provided"). Use it only if natural.
        The friend is a Chinese English learner at this level: \
        \(PromptBuilder.languageGuidance(for: learner.difficulty))
        Their primary goal is: \(PromptBuilder.goalDescription(learner.goal)).
        Their current context is: \(PromptBuilder.stageDescription(learner.studyStage)).
        \(PromptBuilder.interactionGuidance(for: learner.difficulty))
        Treat that level as a comprehension ceiling, not a reason to use difficult vocabulary. Even for an advanced \
        learner, default to ordinary high-frequency spoken words and do not deliberately show off idioms or rare words.
        Write exactly one natural English chat message of 1-2 short sentences and 6-14 words total. Keep one small \
        conversational beat. Sentence-ending punctuation is optional when omitting it feels like natural texting.
        Stay in character and open a topic that supports the primary goal. \(endingInstruction) \
        Sound like a real friend, not a teacher. Do not explain vocabulary, \
        correct grammar, use markdown, or add a speaker label. The UI already identifies the fictional AI role; \
        do not mention it unless directly asked, and never deny it when asked.
        \(RoleplayReplyDiversityPolicy.turnVariationDirective(variation: variationIndex))
        \(recent.isEmpty ? "" : "\nRecent conversation evidence: preserve its facts, plan status, emotional continuity and unanswered turns. Do not mechanically restart a settled topic.\n\(recent)")
        """
    }

    static func normalized(_ raw: String) -> String? {
        var value = raw
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            value.removeFirst()
            value.removeLast()
        }
        var sentenceCount = 0
        value.enumerateSubstrings(
            in: value.startIndex..<value.endIndex,
            options: .bySentences
        ) { substring, _, _, _ in
            if let substring,
               !substring.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sentenceCount += 1
            }
        }
        let wordCount = value.split(whereSeparator: \Character.isWhitespace).count
        guard !value.isEmpty,
              value.count <= 220,
              (1...2).contains(sentenceCount),
              wordCount <= maximumWordsPerMessage,
              value.unicodeScalars.contains(where: {
                  (65...90).contains($0.value) || (97...122).contains($0.value)
              })
        else { return nil }
        return value
    }

    /// 首次联系已经由旅行伙伴安排建立，不能生成“你居然联系我”一类与剧情前提
    /// 冲突的惊讶反应。该校验同时用于升级后修复尚未开始对话的旧开场白。
    public static func isContextuallyValid(
        _ message: String,
        for occasion: Occasion
    ) -> Bool {
        guard occasion == .introduction else { return true }

        let value = message.lowercased()
        if value.contains("am i dreaming")
            || value.contains("phone broken")
            || value.contains("phone is broken")
            || value.contains("phone's broken") {
            return false
        }

        let mentionsContact = value.contains("text")
            || value.contains("messag")
            || value.contains("contact")
        let treatsContactAsUnexpected = value.contains("actually")
            || value.contains("can't believe")
            || value.contains("cannot believe")
            || value.contains("didn't expect")
            || value.contains("did not expect")

        return !(mentionsContact && treatsContactAsUnexpected)
    }

}

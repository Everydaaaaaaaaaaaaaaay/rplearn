import Foundation
import LLMKit
import PersistenceKit

/// 生成角色主动发起的话题。这里只负责文案，发送时机由应用层统一编排。
public struct ProactiveMessageService: Sendable {
    public enum Occasion: Sendable, Equatable {
        /// 刚成为好友时的第一条消息。
        case introduction
        /// 一段时间没有交流后的自然问候。
        case checkIn
    }

    private let llm: any LLMClient

    public init(llm: any LLMClient) {
        self.llm = llm
    }

    /// 始终返回可发送的英文消息；网络或模型失败时使用不依赖具体角色硬编码的本地兜底。
    public func generate(
        for character: CharacterDTO,
        learner: LearnerContext,
        occasion: Occasion,
        recentMessages: [MessageDTO] = []
    ) async -> String {
        let request = LLMRequest(
            task: .conversation,
            tier: .fast,
            system: Self.prompt(
                character: character,
                learner: learner,
                occasion: occasion,
                recentMessages: recentMessages
            ),
            messages: [.user("Write the message now.")],
            maxTokens: 120,
            temperature: 0.9
        )

        if let output = try? await llm.complete(request),
           let message = Self.normalized(output) {
            return message
        }
        return Self.fallback(for: character, learner: learner, occasion: occasion)
    }

    static func prompt(
        character: CharacterDTO,
        learner: LearnerContext,
        occasion: Occasion,
        recentMessages: [MessageDTO]
    ) -> String {
        let card = character.card
        let situation = switch occasion {
        case .introduction:
            """
            You have just become friends. Send the first message yourself and open a topic that is \
            easy and interesting for this person to answer.
            """
        case .checkIn:
            """
            You are checking in after some quiet time. Mention a small, believable detail from your \
            own day, then open a fresh topic. Do not guilt the friend for being away or mention how \
            long they have been silent.
            """
        }
        let recent = recentMessages
            .suffix(8)
            .map { message in
                let speaker = message.role == .user ? "Friend" : card.name
                return "\(speaker): \(message.text)"
            }
            .joined(separator: "\n")

        return """
        You are \(card.name), a \(card.age)-year-old \(card.nationality) person living in \(card.regionID).
        Occupation: \(card.occupation)
        Hobbies: \(card.hobbies.joined(separator: ", "))
        Personality: \(card.personality)
        \(card.speechStyle.map { "Speech style: \($0)" } ?? "")
        \(card.background.map { "Background: \($0)" } ?? "")

        \(situation)

        The friend's preferred name is \(learner.nickname ?? "not provided"). Use it only if natural.
        The friend is a Chinese English learner at this level: \
        \(PromptBuilder.languageGuidance(for: learner.difficulty))
        Their primary goal is: \(PromptBuilder.goalDescription(learner.goal)).
        Their current context is: \(PromptBuilder.stageDescription(learner.studyStage)).
        \(PromptBuilder.interactionGuidance(for: learner.difficulty))
        Write exactly one natural English chat message of 1-2 short sentences and at most 45 words.
        Stay in character, open a topic that supports the primary goal, and end with an approachable question. \
        Sound like a real friend, not a teacher. Do not explain vocabulary, \
        correct grammar, use markdown, add a speaker label, or say you are an AI.
        \(recent.isEmpty ? "" : "\nAvoid repeating these recent topics:\n\(recent)")
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
        guard !value.isEmpty,
              value.count <= 320,
              value.unicodeScalars.contains(where: {
                  (65...90).contains($0.value) || (97...122).contains($0.value)
              })
        else { return nil }
        return value
    }

    static func fallback(
        for character: CharacterDTO,
        learner: LearnerContext,
        occasion: Occasion
    ) -> String {
        if [.primary1, .primary2, .primary3].contains(learner.difficulty) {
            return switch learner.goal {
            case .travel:
                "Hi! Let’s take a trip. Train or plane?"
            case .school, .exam:
                "Hi! What English word do you like?"
            case .studyAbroad:
                "Hi! Would you like a big school or a small school?"
            case .work:
                "Hi! What job do you like?"
            case .culture:
                "Hi! What food is special in your city?"
            case .dailyConversation:
                "Hi! How is your day: good or busy?"
            }
        }

        let occupation = character.card.occupation
        let englishOccupation = occupation.unicodeScalars.allSatisfy { $0.value < 128 }
            ? occupation.trimmingCharacters(in: .whitespacesAndNewlines)
            : ""

        if !englishOccupation.isEmpty {
            return switch occasion {
            case .introduction:
                "Hey! My work as \(englishOccupation) gives me plenty of stories. What kind of job would you love to try for one day?"
            case .checkIn:
                "Something at work made me curious today: what’s one small thing that can instantly make your day better?"
            }
        }

        return switch occasion {
        case .introduction:
            "Hey! I’ve got a question we could have fun comparing: what’s a small part of your day that you really enjoy?"
        case .checkIn:
            "Hey, I’m taking a little break and thought of you. What’s something you’ve been enjoying lately?"
        }
    }
}

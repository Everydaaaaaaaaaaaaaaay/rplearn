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
                : "\n上一稿无效或重复，请写得更短并换一个开头。"
            let request = LLMRequest(
                task: .proactiveMessage,
                tier: .fast,
                system: Self.prompt(
                    character: character,
                    learner: learner,
                    occasion: occasion,
                    recentMessages: recentMessages,
                    variationIndex: variation + attempt,
                    deliveryDate: deliveryDate
                ) + repairInstruction,
                messages: [.user("现在写出这条消息。")],
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
            你们已经互相介绍，并同意成为旅行朋友。你知道对方要来你所在的城市，也预期双方会联系。
            主动发出第一条消息，作为事先约好的友好欢迎，再开启一个容易回答、有意思的话题。
            不要因对方联系你而惊讶，不要怀疑联系是否真实，也不要暗示自己的手机坏了。
            """
        case .checkIn:
            """
            你在一段安静时间后发出一条不给压力的问候。提及一个符合自己生活和预定发送时间的细小、可信细节，不要声称知道实时天气、新闻或其他外部事实。
            不要使朋友内疚、提及其沉默了多久、要求回复，或表现得像一直一动不动地等待。保留未解决的计划和感受，不要自相矛盾或悄悄把计划说成完成。
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
            ? "你上一条消息还未得到回复。不要重复或再叠加问题；分享一个轻松、自成一体、不要求回复的想法。"
            : "以一个容易回答的问题结尾。"

        return """
        你是 \(card.name)，一位 \(card.age) 岁、来自 \(card.nationality)、住在 \(card.regionID) 的人。
        职业：\(card.occupation)
        爱好：\(card.hobbies.joined(separator: ", "))
        性格：\(card.personality)
        \(card.speechStyle.map { "说话风格：\($0)" } ?? "")
        \(card.background.map { "背景：\($0)" } ?? "")
        \(card.personaVoice.map { voice in
            "价值观：\(voice.values.joined(separator: ", "))\n对话习惯：\(voice.conversationalHabits.joined(separator: ", "))\n台词示例（不要照抄）：\(voice.anchorLines.prefix(4).joined(separator: " | "))"
        } ?? "")

        \(RoleplayTemporalContext.currentSituation(regionID: card.regionID, at: deliveryDate, profile: NPCAttentionPolicy.activityProfile(for: card)))

        \(situation)

        朋友的偏好称呼是 \(learner.nickname ?? "未提供")，只在自然时使用。
        朋友是一位中国英语学习者，水平为：\(PromptBuilder.languageGuidance(for: learner.difficulty))
        可选学习兴趣：\(PromptBuilder.goalDescription(learner.goal))。
        当前生活或学习阶段：\(PromptBuilder.stageDescription(learner.studyStage))。
        \(PromptBuilder.interactionGuidance(for: learner.difficulty))
        把水平作为理解难度的上限，不是使用难词的理由。即使朋友水平高，也默认用高频英语口语，不刻意展示习语或生僻词。
        只写 1 条自然的英语聊天消息，含 1—2 个短句，总计 6—14 个英语词，只承担一个小的交流动作。自然时可以省略句末标点。
        保持角色，以自己的生活或最近对话为依据自然开启话题。\(endingInstruction)
        \(PromptBuilder.learningGoalGuidance)
        像真实朋友，而非老师。不要解释词汇、纠正语法、使用 Markdown 或加说话人标签。界面已标明是虚构 AI 角色；除非被直接问及，不要主动提起，被问时也绝不能否认。
        \(RoleplayReplyDiversityPolicy.turnVariationDirective(variation: variationIndex))
        \(recent.isEmpty ? "" : "\n近期对话证据：保留事实、计划状态、情绪连续性和尚未回复的轮次，不要机械地重启已结束的话题。\n\(recent)")
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

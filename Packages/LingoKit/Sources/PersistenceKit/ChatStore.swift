import CoreKit
import Foundation
import SwiftData

/// 聊天仓库：会话与消息的全部写操作。
@ModelActor
public actor ChatStore {
    public enum ChatError: Error {
        case characterNotFound
        case conversationNotFound
    }

    /// 取角色的主会话，没有则创建。
    public func openConversation(characterID: UUID, isEncounterSession: Bool = false) throws -> ConversationDTO {
        guard let character = try modelContext.fetch(
            FetchDescriptor<CharacterEntity>(predicate: #Predicate { $0.characterID == characterID })
        ).first else {
            throw ChatError.characterNotFound
        }
        if let existing = character.conversations.first(where: { !$0.isArchived }) {
            return Self.dto(from: existing, characterID: characterID)
        }
        let conversation = ConversationEntity(isEncounterSession: isEncounterSession)
        conversation.character = character
        modelContext.insert(conversation)
        try modelContext.save()
        return Self.dto(from: conversation, characterID: characterID)
    }

    public func conversation(id: UUID) throws -> ConversationDTO? {
        guard let entity = try fetchConversation(id: id) else { return nil }
        return Self.dto(from: entity, characterID: entity.character?.characterID ?? UUID())
    }

    /// 按 orderIndex 升序取全部消息。
    public func messages(conversationID: UUID) throws -> [MessageDTO] {
        guard let conversation = try fetchConversation(id: conversationID) else {
            throw ChatError.conversationNotFound
        }
        return conversation.messages
            .sorted { $0.orderIndex < $1.orderIndex }
            .map(Self.dto(from:))
    }

    /// 追加一条消息，返回落库后的 DTO（orderIndex 自动递增）。
    @discardableResult
    public func appendMessage(
        conversationID: UUID,
        role: MessageRole,
        kind: MessageKind = .text,
        text: String,
        audioFileName: String? = nil,
        audioDuration: Double? = nil,
        tokenEstimate: Int = 0
    ) throws -> MessageDTO {
        guard let conversation = try fetchConversation(id: conversationID) else {
            throw ChatError.conversationNotFound
        }
        let nextIndex = (conversation.messages.map(\.orderIndex).max() ?? -1) + 1
        let message = MessageEntity(
            roleRaw: role.rawValue,
            kindRaw: kind.rawValue,
            text: text,
            audioFileName: audioFileName,
            audioDuration: audioDuration,
            orderIndex: nextIndex,
            tokenEstimate: tokenEstimate
        )
        message.conversation = conversation
        modelContext.insert(message)
        conversation.lastMessageAt = .now
        if role == .assistant {
            conversation.turnCount += 1
            conversation.turnsSinceQuiz += 1
        }
        try modelContext.save()
        return Self.dto(from: message)
    }

    /// 更新消息文本（流式增量写入 / 结束时定稿）。
    public func updateMessageText(messageID: UUID, text: String, isInterrupted: Bool = false, tokenEstimate: Int? = nil) throws {
        guard let message = try fetchMessage(id: messageID) else { return }
        message.text = text
        message.isInterrupted = isInterrupted
        if let tokenEstimate {
            message.tokenEstimate = tokenEstimate
        }
        try modelContext.save()
    }

    public func setKeywordRanges(messageID: UUID, json: String?) throws {
        guard let message = try fetchMessage(id: messageID) else { return }
        message.keywordRangesJSON = json
        try modelContext.save()
    }

    public func setCoachReview(messageID: UUID, json: String?) throws {
        guard let message = try fetchMessage(id: messageID) else { return }
        message.coachReviewJSON = json
        try modelContext.save()
    }

    public func setTranslation(messageID: UUID, translationZh: String) throws {
        guard let message = try fetchMessage(id: messageID) else { return }
        message.translationZh = translationZh
        try modelContext.save()
    }

    // MARK: - 语境出题（plan.md §3.8）

    /// 出题成功：把 quiz 挂到该助手消息，并清零本会话的 turnsSinceQuiz。
    public func attachQuiz(messageID: UUID, quizJSON: String, conversationID: UUID) throws {
        guard let message = try fetchMessage(id: messageID) else { return }
        message.quizJSON = quizJSON
        if let conversation = try fetchConversation(id: conversationID) {
            conversation.turnsSinceQuiz = 0
        }
        try modelContext.save()
    }

    /// 出题指令已发但模型未产出 quiz：仅清零计数，避免每轮重复追加指令。
    public func resetQuizCounter(conversationID: UUID) throws {
        guard let conversation = try fetchConversation(id: conversationID) else { return }
        conversation.turnsSinceQuiz = 0
        try modelContext.save()
    }

    /// 本会话「不再弹题」开关。
    public func setQuizOptOut(conversationID: UUID, optedOut: Bool) throws {
        guard let conversation = try fetchConversation(id: conversationID) else { return }
        conversation.quizOptOut = optedOut
        try modelContext.save()
    }

    /// 作答：记录选项到消息，并写一条出题记录（供后续统计）。
    public func recordQuizAnswer(
        messageID: UUID,
        chosenIndex: Int,
        question: String,
        optionsJSON: String,
        correctIndex: Int,
        characterName: String?
    ) throws {
        guard let message = try fetchMessage(id: messageID), message.quizChosenIndex == nil else { return }
        message.quizChosenIndex = chosenIndex
        let record = QuizRecordEntity(
            question: question,
            optionsJSON: optionsJSON,
            correctIndex: correctIndex,
            chosenIndex: chosenIndex,
            characterName: characterName
        )
        modelContext.insert(record)
        try modelContext.save()
    }

    /// 归档某角色的全部会话（偶遇未加好友离开后只读，plan.md §3.7）。
    public func archiveConversations(characterID: UUID) throws {
        let conversations = try modelContext.fetch(
            FetchDescriptor<ConversationEntity>(
                predicate: #Predicate { $0.character?.characterID == characterID }
            )
        )
        for conversation in conversations {
            conversation.isArchived = true
        }
        try modelContext.save()
    }

    /// 记忆压缩成功后推进已压缩游标（只进不退）。
    public func setLastSummarizedIndex(conversationID: UUID, index: Int) throws {
        guard let conversation = try fetchConversation(id: conversationID) else {
            throw ChatError.conversationNotFound
        }
        conversation.lastSummarizedMessageIndex = max(conversation.lastSummarizedMessageIndex, index)
        try modelContext.save()
    }

    public func deleteMessage(messageID: UUID) throws {
        guard let message = try fetchMessage(id: messageID) else { return }
        modelContext.delete(message)
        try modelContext.save()
    }

    /// 会话列表（消息 tab）：每个未归档会话一行。
    public func conversationSummaries() throws -> [ConversationSummaryDTO] {
        let conversations = try modelContext.fetch(
            FetchDescriptor<ConversationEntity>(predicate: #Predicate { !$0.isArchived })
        )
        return conversations.compactMap { conversation -> ConversationSummaryDTO? in
            guard let character = conversation.character else { return nil }
            let lastMessage = conversation.messages.max { $0.orderIndex < $1.orderIndex }
            return ConversationSummaryDTO(
                conversationID: conversation.conversationID,
                characterID: character.characterID,
                characterName: character.name,
                avatarAssetName: character.avatarAssetName,
                lastMessageText: lastMessage?.text ?? "",
                lastMessageAt: conversation.lastMessageAt
            )
        }
        .sorted { $0.lastMessageAt > $1.lastMessageAt }
    }

    // MARK: - 私有

    private func fetchConversation(id: UUID) throws -> ConversationEntity? {
        try modelContext.fetch(
            FetchDescriptor<ConversationEntity>(predicate: #Predicate { $0.conversationID == id })
        ).first
    }

    private func fetchMessage(id: UUID) throws -> MessageEntity? {
        try modelContext.fetch(
            FetchDescriptor<MessageEntity>(predicate: #Predicate { $0.messageID == id })
        ).first
    }

    static func dto(from entity: ConversationEntity, characterID: UUID) -> ConversationDTO {
        ConversationDTO(
            id: entity.conversationID,
            characterID: characterID,
            createdAt: entity.createdAt,
            lastMessageAt: entity.lastMessageAt,
            turnCount: entity.turnCount,
            turnsSinceQuiz: entity.turnsSinceQuiz,
            quizOptOut: entity.quizOptOut,
            lastSummarizedMessageIndex: entity.lastSummarizedMessageIndex,
            isEncounterSession: entity.isEncounterSession,
            isArchived: entity.isArchived
        )
    }

    static func dto(from entity: MessageEntity) -> MessageDTO {
        MessageDTO(
            id: entity.messageID,
            role: MessageRole(rawValue: entity.roleRaw) ?? .assistant,
            kind: MessageKind(rawValue: entity.kindRaw) ?? .text,
            text: entity.text,
            audioFileName: entity.audioFileName,
            audioDuration: entity.audioDuration,
            orderIndex: entity.orderIndex,
            tokenEstimate: entity.tokenEstimate,
            keywordRangesJSON: entity.keywordRangesJSON,
            coachReviewJSON: entity.coachReviewJSON,
            quizJSON: entity.quizJSON,
            quizChosenIndex: entity.quizChosenIndex,
            translationZh: entity.translationZh,
            isInterrupted: entity.isInterrupted,
            createdAt: entity.createdAt
        )
    }
}

/// 会话列表行摘要。
public struct ConversationSummaryDTO: Sendable, Equatable, Identifiable {
    public var conversationID: UUID
    public var characterID: UUID
    public var characterName: String
    public var avatarAssetName: String?
    public var lastMessageText: String
    public var lastMessageAt: Date

    public var id: UUID { conversationID }

    public init(
        conversationID: UUID,
        characterID: UUID,
        characterName: String,
        avatarAssetName: String?,
        lastMessageText: String,
        lastMessageAt: Date
    ) {
        self.conversationID = conversationID
        self.characterID = characterID
        self.characterName = characterName
        self.avatarAssetName = avatarAssetName
        self.lastMessageText = lastMessageText
        self.lastMessageAt = lastMessageAt
    }
}

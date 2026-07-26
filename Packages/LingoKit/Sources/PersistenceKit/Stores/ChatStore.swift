import CoreKit
import Foundation
import SwiftData

/// 聊天仓库：会话与消息的全部写操作。
@ModelActor
public actor ChatStore {
    public enum ChatError: Error {
        case characterNotFound
        case conversationNotFound
        case voiceMediaConflict
        case voiceMessageNotFound
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
        try journal(conversation)
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
            .map(dto(from:))
    }

    /// 追加一条消息，返回落库后的 DTO（orderIndex 自动递增）。
    @discardableResult
    public func appendMessage(
        messageID: UUID = UUID(),
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
            messageID: messageID,
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
        try journal(message)
        try journal(conversation)
        try modelContext.save()
        return dto(from: message)
    }

    /// 将模型的一次回复保存为多条连续气泡，但会话轮次只递增一次。
    ///
    /// 角色可以像真人一样连续发送几条短消息，同时剧情进度、测验频率仍按一次
    /// 用户与角色的往返计算。
    public func appendAssistantReply(
        conversationID: UUID,
        texts: [String]
    ) throws -> [MessageDTO] {
        guard let conversation = try fetchConversation(id: conversationID) else {
            throw ChatError.conversationNotFound
        }
        let parts = texts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return [] }

        let firstIndex = (conversation.messages.map(\.orderIndex).max() ?? -1) + 1
        var inserted: [MessageEntity] = []
        inserted.reserveCapacity(parts.count)

        for (offset, text) in parts.enumerated() {
            let message = MessageEntity(
                roleRaw: MessageRole.assistant.rawValue,
                text: text,
                orderIndex: firstIndex + offset,
                tokenEstimate: TokenEstimator.estimate(text)
            )
            message.conversation = conversation
            modelContext.insert(message)
            try journal(message)
            inserted.append(message)
        }

        conversation.lastMessageAt = .now
        conversation.turnCount += 1
        conversation.turnsSinceQuiz += 1
        try journal(conversation)
        try modelContext.save()
        return inserted.map(dto(from:))
    }

    /// 更新消息文本（流式增量写入 / 结束时定稿）。
    public func updateMessageText(messageID: UUID, text: String, isInterrupted: Bool = false, tokenEstimate: Int? = nil) throws {
        guard let message = try fetchMessage(id: messageID) else { return }
        message.text = text
        message.isInterrupted = isInterrupted
        if let tokenEstimate {
            message.tokenEstimate = tokenEstimate
        }
        try journal(message)
        try modelContext.save()
    }

    public func setKeywordRanges(messageID: UUID, json: String?) throws {
        guard let message = try fetchMessage(id: messageID) else { return }
        message.keywordRangesJSON = json
        try journal(message)
        try modelContext.save()
    }

    public func setCoachReview(messageID: UUID, json: String?) throws {
        guard let message = try fetchMessage(id: messageID) else { return }
        message.coachReviewJSON = json
        try journal(message)
        try modelContext.save()
    }

    public func setSpeechReview(messageID: UUID, json: String?) throws {
        guard let message = try fetchMessage(id: messageID) else { return }
        message.speechReviewJSON = json
        try journal(message)
        try modelContext.save()
    }

    public func setTranslation(messageID: UUID, translationZh: String) throws {
        guard let message = try fetchMessage(id: messageID) else { return }
        message.translationZh = translationZh
        try journal(message)
        try modelContext.save()
    }

    public func stageVoiceMediaUpload(_ upload: PendingVoiceMediaUpload) throws {
        guard let message = try fetchMessage(id: upload.messageID) else {
            throw ChatError.voiceMessageNotFound
        }
        let link = try voiceMediaLink(messageID: upload.messageID) ?? {
            let created = VoiceMediaLinkEntity(messageID: upload.messageID)
            modelContext.insert(created)
            return created
        }()
        guard link.assetID == nil || link.assetID == upload.assetID else {
            throw ChatError.voiceMediaConflict
        }
        link.assetID = upload.assetID
        link.isRemoteReady = false
        link.localFileName = upload.localFileName
        link.updatedAt = .now
        message.audioFileName = upload.localFileName
        let assetID = upload.assetID
        let existingUpload = try modelContext.fetch(
            FetchDescriptor<VoiceMediaUploadEntity>(
                predicate: #Predicate { $0.assetID == assetID }
            )
        ).first
        if let existingUpload {
            guard existingUpload.ownerUserID == upload.ownerUserID,
                  existingUpload.messageID == upload.messageID,
                  existingUpload.localFileName == upload.localFileName,
                  existingUpload.byteSize == upload.byteSize,
                  existingUpload.checksumSha256 == upload.checksumSha256,
                  existingUpload.contentType == upload.contentType
            else {
                throw ChatError.voiceMediaConflict
            }
        } else {
            modelContext.insert(
                VoiceMediaUploadEntity(
                    assetID: upload.assetID,
                    ownerUserID: upload.ownerUserID,
                    messageID: upload.messageID,
                    localFileName: upload.localFileName,
                    byteSize: upload.byteSize,
                    checksumSha256: upload.checksumSha256,
                    contentType: upload.contentType
                )
            )
        }
        try modelContext.save()
    }

    public func markVoiceMediaReady(
        messageID: UUID,
        assetID: UUID
    ) throws -> Bool {
        guard let message = try fetchMessage(id: messageID),
              let link = try voiceMediaLink(messageID: messageID),
              link.assetID == assetID
        else { return false }
        link.isRemoteReady = true
        link.updatedAt = .now
        try journal(message)
        try modelContext.save()
        return true
    }

    public func setDownloadedVoiceFileName(
        messageID: UUID,
        assetID: UUID,
        fileName: String
    ) throws {
        guard let message = try fetchMessage(id: messageID) else { return }
        let link = try voiceMediaLink(messageID: messageID) ?? {
            let created = VoiceMediaLinkEntity(
                messageID: messageID,
                assetID: assetID,
                isRemoteReady: true
            )
            modelContext.insert(created)
            return created
        }()
        guard link.assetID == nil || link.assetID == assetID else { return }
        link.assetID = assetID
        link.isRemoteReady = true
        link.localFileName = fileName
        link.updatedAt = .now
        message.audioFileName = fileName
        try modelContext.save()
    }

    // MARK: - 语境出题（plan.md §3.8）

    /// 出题成功：把 quiz 挂到该助手消息，并清零本会话的 turnsSinceQuiz。
    public func attachQuiz(messageID: UUID, quizJSON: String, conversationID: UUID) throws {
        guard let message = try fetchMessage(id: messageID) else { return }
        message.quizJSON = quizJSON
        if let conversation = try fetchConversation(id: conversationID) {
            conversation.turnsSinceQuiz = 0
            try journal(conversation)
        }
        try journal(message)
        try modelContext.save()
    }

    /// 出题指令已发但模型未产出 quiz：仅清零计数，避免每轮重复追加指令。
    public func resetQuizCounter(conversationID: UUID) throws {
        guard let conversation = try fetchConversation(id: conversationID) else { return }
        conversation.turnsSinceQuiz = 0
        try journal(conversation)
        try modelContext.save()
    }

    /// 本会话「不再弹题」开关。
    public func setQuizOptOut(conversationID: UUID, optedOut: Bool) throws {
        guard let conversation = try fetchConversation(id: conversationID) else { return }
        conversation.quizOptOut = optedOut
        try journal(conversation)
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
        try journal(message)
        try modelContext.save()
        try journal(record)
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
            try journal(conversation)
        }
        try modelContext.save()
    }

    /// 记忆压缩成功后推进已压缩游标（只进不退）。
    public func setLastSummarizedIndex(conversationID: UUID, index: Int) throws {
        guard let conversation = try fetchConversation(id: conversationID) else {
            throw ChatError.conversationNotFound
        }
        conversation.lastSummarizedMessageIndex = max(conversation.lastSummarizedMessageIndex, index)
        try journal(conversation)
        try modelContext.save()
    }

    public func deleteMessage(messageID: UUID) throws {
        guard let message = try fetchMessage(id: messageID) else { return }
        try ContentMutationJournal.delete(
            in: modelContext,
            resourceType: .message,
            resourceID: message.messageID.uuidString.lowercased()
        )
        if let upload = try modelContext.fetch(
            FetchDescriptor<VoiceMediaUploadEntity>(
                predicate: #Predicate { $0.messageID == messageID }
            )
        ).first {
            modelContext.delete(upload)
        }
        if let link = try voiceMediaLink(messageID: messageID) {
            modelContext.delete(link)
        }
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
                lastMessageAt: conversation.lastMessageAt,
                lastMessageRole: lastMessage.flatMap { MessageRole(rawValue: $0.roleRaw) },
                lastMessageKind: lastMessage.flatMap { MessageKind(rawValue: $0.kindRaw) }
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

    private func voiceMediaLink(messageID: UUID) throws -> VoiceMediaLinkEntity? {
        try modelContext.fetch(
            FetchDescriptor<VoiceMediaLinkEntity>(
                predicate: #Predicate { $0.messageID == messageID }
            )
        ).first
    }

    private func journal(_ conversation: ConversationEntity) throws {
        guard let characterID = conversation.character?.characterID else { return }
        try ContentMutationJournal.upsert(
            in: modelContext,
            resourceType: .conversation,
            resourceID: conversation.conversationID.uuidString.lowercased(),
            parentID: characterID.uuidString.lowercased(),
            payloadJSON: try ContentMutationJournal.encode(
                ContentConversationPayload(
                    createdAt: conversation.createdAt,
                    isArchived: conversation.isArchived,
                    isEncounterSession: conversation.isEncounterSession,
                    lastMessageAt: conversation.lastMessageAt,
                    lastSummarizedMessageIndex: conversation.lastSummarizedMessageIndex,
                    quizOptOut: conversation.quizOptOut,
                    turnCount: conversation.turnCount,
                    turnsSinceQuiz: conversation.turnsSinceQuiz
                )
            )
        )
    }

    private func journal(_ message: MessageEntity) throws {
        guard let conversationID = message.conversation?.conversationID else { return }
        let media = try voiceMediaLink(messageID: message.messageID)
        try ContentMutationJournal.upsert(
            in: modelContext,
            resourceType: .message,
            resourceID: message.messageID.uuidString.lowercased(),
            parentID: conversationID.uuidString.lowercased(),
            payloadJSON: try ContentMutationJournal.encode(
                ContentMessagePayload(
                    audioAssetId: media?.isRemoteReady == true ? media?.assetID : nil,
                    audioDuration: message.audioDuration,
                    coachReviewJson: message.coachReviewJSON,
                    createdAt: message.createdAt,
                    isInterrupted: message.isInterrupted,
                    keywordRangesJson: message.keywordRangesJSON,
                    kind: message.kindRaw,
                    orderIndex: message.orderIndex,
                    quizChosenIndex: message.quizChosenIndex,
                    quizJson: message.quizJSON,
                    role: message.roleRaw,
                    speechReviewJson: message.speechReviewJSON,
                    text: message.text,
                    tokenEstimate: message.tokenEstimate,
                    translationZh: message.translationZh
                )
            )
        )
    }

    private func journal(_ quiz: QuizRecordEntity) throws {
        guard let chosenIndex = quiz.chosenIndex else { return }
        let localKey = ContentMutationJournal.persistentKey(quiz.persistentModelID)
        let resourceID = try ContentMutationJournal.resourceID(
            in: modelContext,
            resourceType: .quizRecord,
            localKey: localKey
        )
        try ContentMutationJournal.upsert(
            in: modelContext,
            resourceType: .quizRecord,
            resourceID: resourceID,
            parentID: nil,
            payloadJSON: try ContentMutationJournal.encode(
                ContentQuizRecordPayload(
                    characterName: quiz.characterName,
                    chosenIndex: chosenIndex,
                    correctIndex: quiz.correctIndex,
                    createdAt: quiz.createdAt,
                    optionsJson: quiz.optionsJSON,
                    question: quiz.question
                )
            )
        )
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

    private func dto(from entity: MessageEntity) -> MessageDTO {
        let media = try? voiceMediaLink(messageID: entity.messageID)
        return MessageDTO(
            id: entity.messageID,
            role: MessageRole(rawValue: entity.roleRaw) ?? .assistant,
            kind: MessageKind(rawValue: entity.kindRaw) ?? .text,
            text: entity.text,
            audioAssetID: media?.isRemoteReady == true ? media?.assetID : nil,
            audioFileName: media?.localFileName ?? entity.audioFileName,
            audioDuration: entity.audioDuration,
            orderIndex: entity.orderIndex,
            tokenEstimate: entity.tokenEstimate,
            keywordRangesJSON: entity.keywordRangesJSON,
            coachReviewJSON: entity.coachReviewJSON,
            speechReviewJSON: entity.speechReviewJSON,
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
    public var lastMessageRole: MessageRole?
    public var lastMessageKind: MessageKind?

    public var id: UUID { conversationID }

    public init(
        conversationID: UUID,
        characterID: UUID,
        characterName: String,
        avatarAssetName: String?,
        lastMessageText: String,
        lastMessageAt: Date,
        lastMessageRole: MessageRole? = nil,
        lastMessageKind: MessageKind? = nil
    ) {
        self.conversationID = conversationID
        self.characterID = characterID
        self.characterName = characterName
        self.avatarAssetName = avatarAssetName
        self.lastMessageText = lastMessageText
        self.lastMessageAt = lastMessageAt
        self.lastMessageRole = lastMessageRole
        self.lastMessageKind = lastMessageKind
    }
}

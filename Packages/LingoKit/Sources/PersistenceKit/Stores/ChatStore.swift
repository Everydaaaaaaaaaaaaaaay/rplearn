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
        case activityIdentityConflict
    }

    /// 取角色的主会话，没有则创建。
    public func openConversation(characterID: UUID, isEncounterSession: Bool = false) throws -> ConversationDTO {
        guard let character = try modelContext.fetch(
            FetchDescriptor<CharacterEntity>(predicate: #Predicate { $0.characterID == characterID })
        ).first else {
            throw ChatError.characterNotFound
        }
        if let existing = character.conversations.first(where: { !$0.isArchived }) {
            if character.isFriend && existing.isEncounterSession {
                existing.isEncounterSession = false
                try journal(existing)
                try modelContext.save()
            }
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

    /// 置顶是用户私有会话偏好，写入 SwiftData 并进入内容同步 Outbox。
    public func setPinned(conversationID: UUID, isPinned: Bool) throws {
        guard let conversation = try fetchConversation(id: conversationID) else {
            throw ChatError.conversationNotFound
        }
        guard conversation.isPinned != isPinned else { return }
        conversation.isPinned = isPinned
        try journal(conversation)
        try modelContext.save()
    }

    /// 已读时间只前进不后退，避免多设备或异步刷新覆盖较新的阅读进度。
    public func markRead(conversationID: UUID, at date: Date = .now) throws {
        guard let conversation = try fetchConversation(id: conversationID) else {
            throw ChatError.conversationNotFound
        }
        guard (conversation.lastReadAt ?? .distantPast) < date else { return }
        conversation.lastReadAt = date
        try journal(conversation)
        try modelContext.save()
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

    /// 多个聊天页面或重启恢复同时尝试回复时，只允许仍位于时间线末端的用户消息继续。
    public func isLatestUnansweredUserMessage(
        conversationID: UUID,
        messageID: UUID,
        replacingAssistantMessageID: UUID? = nil
    ) throws -> Bool {
        guard let conversation = try fetchConversation(id: conversationID) else {
            throw ChatError.conversationNotFound
        }
        let latestDialogueMessage = conversation.messages
            .filter {
                $0.roleRaw == MessageRole.user.rawValue
                    || $0.roleRaw == MessageRole.assistant.rawValue
            }
            .max { lhs, rhs in
                if lhs.orderIndex == rhs.orderIndex {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.orderIndex < rhs.orderIndex
            }
        if let replacingAssistantMessageID {
            return latestDialogueMessage?.roleRaw == MessageRole.assistant.rawValue
                && latestDialogueMessage?.messageID == replacingAssistantMessageID
        }
        return latestDialogueMessage?.roleRaw == MessageRole.user.rawValue
            && latestDialogueMessage?.messageID == messageID
    }

    /// 清空该角色的聊天记录但保留角色、好友关系和关系成长。返回本地语音文件名供媒体层清理。
    @discardableResult
    public func clearConversationHistory(characterID: UUID) throws -> [String] {
        guard let character = try modelContext.fetch(
            FetchDescriptor<CharacterEntity>(predicate: #Predicate { $0.characterID == characterID })
        ).first else {
            throw ChatError.characterNotFound
        }
        var localVoiceFiles: [String] = []
        for conversation in character.conversations {
            for message in conversation.messages {
                if let fileName = message.audioFileName { localVoiceFiles.append(fileName) }
                try ContentMutationJournal.delete(
                    in: modelContext,
                    resourceType: .message,
                    resourceID: message.messageID.uuidString.lowercased()
                )
                let messageID = message.messageID
                if let upload = try modelContext.fetch(
                    FetchDescriptor<VoiceMediaUploadEntity>(
                        predicate: #Predicate { $0.messageID == messageID }
                    )
                ).first {
                    modelContext.delete(upload)
                }
                if let link = try voiceMediaLink(messageID: messageID) {
                    if let fileName = link.localFileName { localVoiceFiles.append(fileName) }
                    try enqueueRemoteVoiceDeletionIfNeeded(link: link, messageID: messageID)
                    modelContext.delete(link)
                }
                modelContext.delete(message)
            }
            conversation.turnCount = 0
            conversation.turnsSinceQuiz = 0
            conversation.lastSummarizedMessageIndex = 0
            conversation.lastMessageAt = conversation.createdAt
            try journal(conversation)
        }
        try modelContext.save()
        return Array(Set(localVoiceFiles))
    }

    /// 读取角色跨当前与归档会话的近期消息，供重新开场时避免重复旧话题。
    public func recentMessages(characterID: UUID, limit: Int = 16) throws -> [MessageDTO] {
        guard let character = try modelContext.fetch(
            FetchDescriptor<CharacterEntity>(predicate: #Predicate { $0.characterID == characterID })
        ).first else {
            throw ChatError.characterNotFound
        }
        return character.conversations
            .flatMap(\.messages)
            .sorted {
                if $0.createdAt == $1.createdAt {
                    return $0.orderIndex < $1.orderIndex
                }
                return $0.createdAt < $1.createdAt
            }
            .suffix(max(0, limit))
            .map(dto(from:))
    }

    /// 角色是否还没有任何聊天内容。供“结识后主动开场”在生成文案前快速判断。
    public func needsInitialMessage(characterID: UUID) throws -> Bool {
        guard let character = try modelContext.fetch(
            FetchDescriptor<CharacterEntity>(predicate: #Predicate { $0.characterID == characterID })
        ).first else {
            throw ChatError.characterNotFound
        }
        return character.conversations
            .filter { !$0.isArchived }
            .allSatisfy(\.messages.isEmpty)
    }

    /// 幂等写入角色的第一条消息；多个入口同时触发时也只会保存一次。
    @discardableResult
    public func appendInitialMessageIfNeeded(
        characterID: UUID,
        text: String
    ) throws -> MessageDTO? {
        guard let character = try modelContext.fetch(
            FetchDescriptor<CharacterEntity>(predicate: #Predicate { $0.characterID == characterID })
        ).first else {
            throw ChatError.characterNotFound
        }
        let conversation: ConversationEntity
        if let existing = character.conversations.first(where: { !$0.isArchived }) {
            guard existing.messages.isEmpty else { return nil }
            conversation = existing
        } else {
            let created = ConversationEntity()
            created.character = character
            modelContext.insert(created)
            try journal(created)
            conversation = created
        }

        let message = MessageEntity(
            roleRaw: MessageRole.assistant.rawValue,
            text: text,
            orderIndex: 0,
            tokenEstimate: TokenEstimator.estimate(text)
        )
        message.conversation = conversation
        modelContext.insert(message)
        conversation.lastMessageAt = message.createdAt
        conversation.turnCount += 1
        conversation.turnsSinceQuiz += 1
        try journal(message)
        try journal(conversation)
        try modelContext.save()
        return dto(from: message)
    }

    /// 仅修复尚未发生真实往来的单条旧开场白。只要用户或角色已经继续发过消息，
    /// 就绝不回写聊天历史。
    @discardableResult
    public func replaceSoleInitialMessageIfNeeded(
        characterID: UUID,
        matching invalidText: String,
        with replacementText: String
    ) throws -> MessageDTO? {
        guard let character = try modelContext.fetch(
            FetchDescriptor<CharacterEntity>(predicate: #Predicate { $0.characterID == characterID })
        ).first,
              let conversation = character.conversations.first(where: { !$0.isArchived }),
              conversation.messages.count == 1,
              let message = conversation.messages.first,
              message.roleRaw == MessageRole.assistant.rawValue,
              message.orderIndex == 0,
              message.text == invalidText
        else { return nil }

        let cleanedReplacement = replacementText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedReplacement.isEmpty else { return nil }

        message.text = cleanedReplacement
        message.tokenEstimate = TokenEstimator.estimate(cleanedReplacement)
        conversation.lastMessageAt = message.createdAt
        try journal(message)
        try journal(conversation)
        try modelContext.save()
        return dto(from: message)
    }

    /// 幂等保存一条已经到期的主动消息。事件 UUID 同时作为消息 UUID，避免重复唤醒造成重复气泡。
    @discardableResult
    public func appendProactiveMessageIfNeeded(
        messageID: UUID,
        characterID: UUID,
        text: String,
        createdAt: Date = .now
    ) throws -> MessageDTO? {
        if try fetchMessage(id: messageID) != nil { return nil }
        guard let character = try modelContext.fetch(
            FetchDescriptor<CharacterEntity>(predicate: #Predicate { $0.characterID == characterID })
        ).first else {
            throw ChatError.characterNotFound
        }
        let conversation: ConversationEntity
        if let existing = character.conversations.first(where: { !$0.isArchived }) {
            conversation = existing
        } else {
            let created = ConversationEntity(
                createdAt: createdAt,
                lastMessageAt: createdAt
            )
            created.character = character
            modelContext.insert(created)
            try journal(created)
            conversation = created
        }
        let nextIndex = (conversation.messages.map(\.orderIndex).max() ?? -1) + 1
        let message = MessageEntity(
            messageID: messageID,
            roleRaw: MessageRole.assistant.rawValue,
            text: text,
            orderIndex: nextIndex,
            tokenEstimate: TokenEstimator.estimate(text),
            createdAt: createdAt
        )
        message.conversation = conversation
        modelContext.insert(message)
        conversation.lastMessageAt = max(conversation.lastMessageAt, message.createdAt)
        conversation.turnCount += 1
        conversation.turnsSinceQuiz += 1
        try journal(message)
        try journal(conversation)
        try modelContext.save()
        return dto(from: message)
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
        tokenEstimate: Int = 0,
        createdAt: Date = .now
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
            tokenEstimate: tokenEstimate,
            createdAt: createdAt
        )
        message.conversation = conversation
        modelContext.insert(message)
        conversation.lastMessageAt = max(conversation.lastMessageAt, createdAt)
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
        texts: [String],
        createdAt: Date = .now
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
                tokenEstimate: TokenEstimator.estimate(text),
                createdAt: createdAt
            )
            message.conversation = conversation
            modelContext.insert(message)
            try journal(message)
            inserted.append(message)
        }

        conversation.lastMessageAt = max(conversation.lastMessageAt, createdAt)
        conversation.turnCount += 1
        conversation.turnsSinceQuiz += 1
        try journal(conversation)
        try modelContext.save()
        return inserted.map(dto(from:))
    }

    /// 逐条保存同一次角色回复，供聊天页模拟真人连续输入的送达节奏。
    ///
    /// 第一条使用 `startsNewReply = true` 递增会话轮次；后续气泡传 false，
    /// 从而使逐条出现的多条消息在剧情和测验统计上仍只算一次回复。
    @discardableResult
    public func appendAssistantReplyPart(
        conversationID: UUID,
        text: String,
        startsNewReply: Bool,
        createdAt: Date = .now
    ) throws -> MessageDTO {
        guard let conversation = try fetchConversation(id: conversationID) else {
            throw ChatError.conversationNotFound
        }
        let cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextIndex = (conversation.messages.map(\.orderIndex).max() ?? -1) + 1
        let message = MessageEntity(
            roleRaw: MessageRole.assistant.rawValue,
            text: cleanedText,
            orderIndex: nextIndex,
            tokenEstimate: TokenEstimator.estimate(cleanedText),
            createdAt: createdAt
        )
        message.conversation = conversation
        modelContext.insert(message)
        conversation.lastMessageAt = message.createdAt
        if startsNewReply {
            conversation.turnCount += 1
            conversation.turnsSinceQuiz += 1
        }
        try journal(message)
        try journal(conversation)
        try modelContext.save()
        return dto(from: message)
    }

    /// 首气泡提交门禁：末端检查与插入位于同一个 ModelActor 临界区，避免用户恰好
    /// 在 UI 层检查通过后补发消息而让旧回复越过新消息。
    public func appendAssistantReplyPartIfCurrent(
        conversationID: UUID,
        text: String,
        respondingToMessageID: UUID,
        replacingAssistantMessageID: UUID? = nil,
        createdAt: Date = .now
    ) throws -> MessageDTO? {
        guard try isLatestUnansweredUserMessage(
            conversationID: conversationID,
            messageID: respondingToMessageID,
            replacingAssistantMessageID: replacingAssistantMessageID
        ) else { return nil }
        return try appendAssistantReplyPart(
            conversationID: conversationID,
            text: text,
            startsNewReply: true,
            createdAt: createdAt
        )
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

    // MARK: - 语境出题

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

    /// 归档某角色的全部会话（偶遇未加好友离开后只读）。
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
            try enqueueRemoteVoiceDeletionIfNeeded(link: link, messageID: messageID)
            modelContext.delete(link)
        }
        modelContext.delete(message)
        try modelContext.save()
    }

    // MARK: - 私有

    /// Commits only an actually revealed scene line, plus its contextual memory.
    /// Retry uses the same UUID. Never archive/replace an existing friend's chat.
    @discardableResult
    public func appendActivityLineIfNeeded(
        messageID: UUID, characterID: UUID, role: MessageRole, text: String,
        translation: String, context: String
    ) throws -> MessageDTO {
        if let existing = try fetchMessage(id: messageID) {
            guard existing.conversation?.character?.characterID == characterID,
                  existing.roleRaw == role.rawValue, existing.text == text else {
                throw ChatError.activityIdentityConflict
            }
            try journalActivityMemory(characterID: characterID, index: existing.orderIndex)
            return dto(from: existing)
        }
        guard let character = try modelContext.fetch(FetchDescriptor<CharacterEntity>(
            predicate: #Predicate { $0.characterID == characterID }
        )).first else { throw ChatError.characterNotFound }
        let conversation: ConversationEntity
        if let current = character.conversations.first(where: { !$0.isArchived }) {
            conversation = current
        } else {
            conversation = ConversationEntity(isEncounterSession: !character.isFriend)
            conversation.character = character
            modelContext.insert(conversation)
        }
        let index = (conversation.messages.map(\.orderIndex).max() ?? -1) + 1
        let message = MessageEntity(messageID: messageID, roleRaw: role.rawValue,
            kindRaw: MessageKind.text.rawValue, text: text, orderIndex: index)
        message.translationZh = translation
        message.conversation = conversation
        modelContext.insert(message)
        conversation.lastMessageAt = message.createdAt
        conversation.lastReadAt = message.createdAt
        if role == .assistant { conversation.turnCount += 1 }
        let memory = MemoryEntity(tierRaw: MemoryTier.short.rawValue, sourceRaw: MemorySource.activity.rawValue,
            content: "\(context)\n\(role == .user ? "用户" : character.name)：\(text)",
            importance: 3, sourceUpToIndex: index)
        memory.character = character
        modelContext.insert(memory)
        do {
            try journal(message)
            try journal(conversation)
            // Commit line and memory together, then bind the permanent SwiftData
            // identity using the same mapping as MemoryStore. Retry repairs outbox.
            try modelContext.save()
            try journalActivityMemory(characterID: characterID, index: index)
            return dto(from: message)
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func journalActivityMemory(characterID: UUID, index: Int) throws {
        let source = MemorySource.activity.rawValue
        let memories = try modelContext.fetch(FetchDescriptor<MemoryEntity>(predicate: #Predicate {
            $0.character?.characterID == characterID && $0.sourceRaw == source && $0.sourceUpToIndex == index
        }))
        for memory in memories {
            let resourceID = try ContentMutationJournal.resourceID(in: modelContext, resourceType: .memory,
                localKey: ContentMutationJournal.persistentKey(memory.persistentModelID))
            try ContentMutationJournal.upsert(in: modelContext, resourceType: .memory,
                resourceID: resourceID, parentID: characterID.uuidString.lowercased(),
                payloadJSON: try ContentMutationJournal.encode(ContentMemoryPayload(
                    content: memory.content, createdAt: memory.createdAt, importance: memory.importance,
                    source: memory.sourceRaw, sourceUpToIndex: index, tier: memory.tierRaw)))
        }
        try modelContext.save()
    }

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

    private func enqueueRemoteVoiceDeletionIfNeeded(
        link: VoiceMediaLinkEntity,
        messageID: UUID
    ) throws {
        guard link.isRemoteReady, let assetID = link.assetID else { return }
        guard let owner = try modelContext.fetch(
            FetchDescriptor<ContentSyncOwnerEntity>(
                predicate: #Predicate { $0.singletonKey == "active" }
            )
        ).first else { return }
        let existing = try modelContext.fetch(
            FetchDescriptor<VoiceMediaDeletionEntity>(
                predicate: #Predicate { $0.assetID == assetID }
            )
        ).first
        guard existing == nil else { return }
        modelContext.insert(
            VoiceMediaDeletionEntity(
                assetID: assetID,
                ownerUserID: owner.userID,
                messageID: messageID
            )
        )
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
                    isPinned: conversation.isPinned,
                    lastMessageAt: conversation.lastMessageAt,
                    lastReadAt: conversation.lastReadAt,
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
            isArchived: entity.isArchived,
            isPinned: entity.isPinned,
            lastReadAt: entity.lastReadAt
        )
    }

    func dto(from entity: MessageEntity) -> MessageDTO {
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

import Foundation

public enum SharedComposerActivity: String, Sendable, Codable {
    case edited, blurred, sent, inactive
}

/// Server acceptance order and input coverage are shared by every signed-in device.
public struct SharedChatSnapshot: Sendable, Equatable {
    public struct ReplyPlan: Sendable, Equatable {
        public let userMessageID: UUID
        public let attention: String
        public let noticedAt: Date
        public let generationStartsAt: Date
        public let typingStartsAt: Date
        public let firstBubbleAt: Date
        public let continuingConversation: Bool
        public init(userMessageID: UUID, attention: String, noticedAt: Date,
                    generationStartsAt: Date, typingStartsAt: Date, firstBubbleAt: Date,
                    continuingConversation: Bool) {
            self.userMessageID = userMessageID
            self.attention = attention
            self.noticedAt = noticedAt
            self.generationStartsAt = generationStartsAt
            self.typingStartsAt = typingStartsAt
            self.firstBubbleAt = firstBubbleAt
            self.continuingConversation = continuingConversation
        }
    }
    public struct Generation: Sendable, Equatable {
        public let id: UUID
        public let status: String
        public let partialText: String
        public let inputMessageIDs: [UUID]
        public let errorCode: String?
        public let phase: String?
        public let replyPlan: ReplyPlan?
        public init(
            id: UUID, status: String, partialText: String, inputMessageIDs: [UUID], errorCode: String? = nil,
            phase: String? = nil, replyPlan: ReplyPlan? = nil
        ) {
            self.id = id
            self.status = status
            self.partialText = partialText
            self.inputMessageIDs = inputMessageIDs
            self.errorCode = errorCode
            self.phase = phase
            self.replyPlan = replyPlan
        }
    }
    public let durableFollowups: Bool
    public let conversationID: UUID
    public let lastSequence: Int
    public let generation: Generation?
    public let coveredMessageIDs: Set<UUID>
    public init(
        conversationID: UUID, lastSequence: Int, generation: Generation?, coveredMessageIDs: Set<UUID>, durableFollowups: Bool = false
    ) {
        self.durableFollowups = durableFollowups
        self.conversationID = conversationID
        self.lastSequence = lastSequence
        self.generation = generation
        self.coveredMessageIDs = coveredMessageIDs
    }
}

public protocol SharedChatGateway: Sendable {
    func openSharedConversation(characterID: UUID) async throws -> SharedChatSnapshot
    func refreshSharedConversation(conversationID: UUID) async throws -> SharedChatSnapshot
    func sharedReply(conversationID: UUID, userMessageID: UUID) async throws -> SharedChatSnapshot
    func recordSharedVoiceReceipt(conversationID: UUID, userMessageID: UUID, text: String, interrupted: Bool) async throws
    func uploadSharedMessages() async throws
    func retrySharedReply(conversationID: UUID, commandID: UUID) async throws
    func reportSharedComposer(conversationID: UUID, sessionID: UUID, sequence: Int,
                              activity: SharedComposerActivity, remaining: TimeInterval) async throws -> Bool
}

extension SharedChatGateway {
    public func recordSharedVoiceReceipt(conversationID: UUID, userMessageID: UUID, text: String, interrupted: Bool) async throws {}
    public func reportSharedComposer(conversationID: UUID, sessionID: UUID, sequence: Int,
                                     activity: SharedComposerActivity, remaining: TimeInterval) async throws -> Bool { true }
}

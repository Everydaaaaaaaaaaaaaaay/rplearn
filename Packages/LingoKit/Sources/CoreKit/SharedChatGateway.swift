import Foundation

/// Server acceptance order and input coverage are shared by every signed-in device.
public struct SharedChatSnapshot: Sendable, Equatable {
    public struct Generation: Sendable, Equatable {
        public let id: UUID
        public let status: String
        public let partialText: String
        public let inputMessageIDs: [UUID]
        public let errorCode: String?
        public init(
            id: UUID, status: String, partialText: String, inputMessageIDs: [UUID], errorCode: String? = nil
        ) {
            self.id = id
            self.status = status
            self.partialText = partialText
            self.inputMessageIDs = inputMessageIDs
            self.errorCode = errorCode
        }
    }
    public let conversationID: UUID
    public let lastSequence: Int
    public let generation: Generation?
    public let coveredMessageIDs: Set<UUID>
    public init(
        conversationID: UUID, lastSequence: Int, generation: Generation?, coveredMessageIDs: Set<UUID>
    ) {
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
    func uploadSharedMessages() async throws
    func retrySharedReply(conversationID: UUID, commandID: UUID) async throws
}

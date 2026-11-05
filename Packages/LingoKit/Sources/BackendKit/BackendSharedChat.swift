import Foundation

public struct BackendSharedChatState: Decodable, Sendable {
    public struct Generation: Decodable, Sendable {
        public let id: UUID
        public let status: String
        public let partialText: String
        public let inputMessageIds: [UUID]
        public let errorCode: String?
    }
    public let protocolVersion: Int
    public let conversationId: UUID
    public let revision: Int
    public let lastSequence: Int
    public let hasMore: Bool
    public let generation: Generation?
    public let coveredMessageIds: [UUID]
    public let records: [BackendContentRecord]
}

extension BackendClient {
    public func openSharedChat(characterID: UUID) async throws -> BackendSharedChatState {
        struct Body: Encodable { let protocolVersion = 1 }
        return try await send(
            path: "/v1/chat/characters/\(characterID.uuidString.lowercased())/open", method: "POST",
            body: Body())
    }
    public func sharedChatState(conversationID: UUID, afterSequence: Int, inputMessageID: UUID? = nil)
        async throws -> BackendSharedChatState
    {
        var query = [URLQueryItem(name: "afterSequence", value: String(afterSequence))]
        if let inputMessageID {
            query.append(URLQueryItem(name: "inputMessageId", value: inputMessageID.uuidString.lowercased()))
        }
        return try await get(
            "/v1/chat/conversations/\(conversationID.uuidString.lowercased())", queryItems: query)
    }
    public func retrySharedChat(conversationID: UUID, commandID: UUID) async throws -> BackendSharedChatState
    {
        struct Body: Encodable { let commandId: UUID }
        return try await send(
            path: "/v1/chat/conversations/\(conversationID.uuidString.lowercased())/retry", method: "POST",
            body: Body(commandId: commandID))
    }
}

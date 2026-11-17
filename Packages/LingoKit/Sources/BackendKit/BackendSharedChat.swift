import Foundation
import CoreKit

public struct BackendSharedChatState: Decodable, Sendable {
    public struct ReplyPlan: Decodable, Sendable {
        public let userMessageId: UUID
        public let attention: String
        public let noticedAt: Double
        public let generationStartsAt: Double
        public let typingStartsAt: Double
        public let firstBubbleAt: Double
        public let continuingConversation: Bool
    }
    public struct Generation: Decodable, Sendable {
        public let id: UUID
        public let status: String
        public let partialText: String
        public let inputMessageIds: [UUID]
        public let errorCode: String?
        public let phase: String?
        public let replyPlan: ReplyPlan?
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
    public func reportChatComposer(conversationID: UUID, sessionID: UUID, sequence: Int,
                                   activity: SharedComposerActivity, remaining: TimeInterval) async throws -> Bool {
        struct Body: Encodable {
            let sessionId: UUID
            let sequence: Int
            let activity: SharedComposerActivity
            let remainingMilliseconds: Double
        }
        struct Response: Decodable { let accepted: Bool }
        let response: Response = try await send(
            path: "/v1/chat/conversations/\(conversationID.uuidString.lowercased())/composer", method: "POST",
            body: Body(sessionId: sessionID, sequence: sequence, activity: activity,
                       remainingMilliseconds: min(25_000, max(0, remaining * 1000))))
        return response.accepted
    }
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

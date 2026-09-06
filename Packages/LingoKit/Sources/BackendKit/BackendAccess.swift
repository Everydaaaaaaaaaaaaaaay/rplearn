import Foundation

public struct BackendAccessSnapshot: Decodable, Sendable {
    public struct Policy: Decodable, Sendable {
        public let isGuest: Bool
        public let plan: String
        public let friendSlotLimit: Int
        public let provisional: Bool
        public let quotaWindow: String
    }
    public struct Balance: Decodable, Sendable {
        public let limit: Int
        public let used: Int
        public let reserved: Int
        public let remaining: Int
    }
    public struct Credits: Decodable, Sendable {
        public struct Entry: Decodable, Sendable, Identifiable {
            public var id: String { operationId }
            public let operationId: String
            public let task: String
            public let status: String
            public let credits: Double?
            public let heldCredits: Double
            public let createdAt: String
        }
        public let limit: Double
        public let used: Double
        public let reserved: Double
        public let pending: Double
        public let remaining: Double
        public let resetsAt: String?
        public let window: String
        public let recent: [Entry]
    }
    public let credits: Credits?
    public let policy: Policy
    public let resetsAt: String?
    public let balances: [String: Balance]
}
public struct BackendVoiceLease: Decodable, Sendable {
    public let operationId: UUID
    public let amount: Int
    public let expiresAt: String
    public let replay: Bool
}
extension BackendClient {
    public func accessSnapshot() async throws -> BackendAccessSnapshot {
        let client = try await actorClient()
        return try await client.get("/v1/access")
    }
    public func reserveVoice(operationID: UUID) async throws -> BackendVoiceLease {
        let client = try await actorClient()
        return try await client.send(path: "/v1/access/voice", method: "POST", body: ["operationId": operationID.uuidString])
    }
    public func stopVoice(operationID: UUID) async throws {
        let client = try await actorClient()
        let _: BackendAccessSnapshot = try await client.send(path: "/v1/access/voice/stop", method: "POST", body: ["operationId": operationID.uuidString])
    }
}

import Foundation

public struct BackendActivityPhoto: Codable, Sendable, Equatable {
    public let id: String
    public let cityId: String
    public let placeId: String
    public let assetName: String
    public let sourceUrl: URL
    public let author: String
    public let license: String
    public let licenseUrl: URL
    public let outputSHA256: String
    public let width: Int
    public let height: Int
}

public struct BackendActivityPlace: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let titleZh: String
    public let category: String
    public let photo: BackendActivityPhoto
}

public struct BackendActivityCatalog: Codable, Sendable, Equatable {
    public let releaseId: String
    public let cityId: String
    public let places: [BackendActivityPlace]
}

public struct BackendOutingBeat: Codable, Sendable, Equatable {
    public let speaker: String
    public let english: String
    public let chinese: String
}

public struct BackendOutingStory: Codable, Sendable, Equatable {
    public struct Node: Codable, Sendable, Equatable {
        public struct Choice: Codable, Sendable, Equatable {
            public let english: String
            public let chinese: String
            public let next: String
        }
        public let id: String
        public let beats: [BackendOutingBeat]
        public let choices: [Choice]
    }
    public struct Reunion: Codable, Sendable, Equatable {
        public let titleZh: String
        public let beats: [BackendOutingBeat]
    }
    public let id: String
    public let titleZh: String
    public let nodes: [Node]
    public let reunion: Reunion
}

public struct BackendOuting: Codable, Sendable, Equatable, Identifiable {
    public enum Status: String, Codable, Sendable { case reserved, opening_presented, in_progress, completed, abandoned }
    public enum Mode: String, Codable, Sendable { case first_meeting, reunion, solitude }
    public enum Reason: String, Codable, Sendable { case encounter, quiet_visit, empty_pool }
    public struct Solitude: Codable, Sendable, Equatable {
        public let id: String
        public let titleZh: String
        public let english: String
        public let chinese: String
    }
    public var id: UUID { runId }
    public let runId: UUID
    public let releaseId: String
    public let cityId: String
    public let placeId: String
    public let placeTitleZh: String
    public let createdAt: String
    public var status: Status
    public var revision: Int
    public let mode: Mode
    public let reason: Reason
    public let npc: BackendPublicNPC?
    public let story: BackendOutingStory?
    public let photo: BackendActivityPhoto
    public let solitude: Solitude
    public var nodeId: String
    public var beatIndex: Int
    public var choices: [String]
}

public struct BackendOutingOperation: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case read, presented, choice, complete, abandon
        var path: String { self == .choice ? "choices" : rawValue }
    }
    public var id: UUID { operationId }
    public let operationId: UUID
    public let expectedRevision: Int
    public let type: Kind
    public let beatIndex: Int?
    public let choiceId: String?
    public init(operationID: UUID = UUID(), expectedRevision: Int, type: Kind, beatIndex: Int? = nil, choiceID: String? = nil) {
        operationId = operationID; self.expectedRevision = expectedRevision; self.type = type
        self.beatIndex = beatIndex; choiceId = choiceID
    }
}

public protocol OutingGateway: Sendable {
    func activityCatalog(releaseID: String?) async throws -> BackendActivityCatalog?
    func activeOuting() async throws -> BackendOuting?
    func outing(id: UUID) async throws -> BackendOuting
    func startOuting(id: UUID, releaseID: String, placeID: String) async throws -> BackendOuting
    func applyOuting(id: UUID, operation: BackendOutingOperation) async throws -> BackendOuting
}

extension BackendClient: OutingGateway {
    public func activityCatalog(releaseID: String? = nil) async throws -> BackendActivityCatalog? {
        struct Reply: Decodable, Sendable { let catalog: BackendActivityCatalog? }
        let query = releaseID.map { [URLQueryItem(name: "releaseId", value: $0)] } ?? []
        let reply: Reply = try await actorClient().get("/v2/activity-world", queryItems: query)
        return reply.catalog
    }
    public func activeOuting() async throws -> BackendOuting? {
        struct Reply: Decodable, Sendable { let outing: BackendOuting? }
        let reply: Reply = try await actorClient().get("/v2/outings/active")
        return reply.outing
    }
    public func outing(id: UUID) async throws -> BackendOuting {
        try await actorClient().get("/v2/outings/\(id.uuidString.lowercased())")
    }
    public func startOuting(id: UUID, releaseID: String, placeID: String) async throws -> BackendOuting {
        struct Body: Encodable, Sendable { let runId: UUID; let releaseId: String; let placeId: String }
        return try await actorClient().send(path: "/v2/outings", method: "POST", body: Body(runId: id, releaseId: releaseID, placeId: placeID))
    }
    public func applyOuting(id: UUID, operation: BackendOutingOperation) async throws -> BackendOuting {
        struct Body: Encodable, Sendable {
            let operationId: UUID; let expectedRevision: Int; let beatIndex: Int?; let choiceId: String?
        }
        let body = Body(operationId: operation.operationId, expectedRevision: operation.expectedRevision,
                        beatIndex: operation.beatIndex, choiceId: operation.choiceId)
        return try await actorClient().send(path: "/v2/outings/\(id.uuidString.lowercased())/\(operation.type.path)", method: "POST", body: body)
    }
}

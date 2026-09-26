import Foundation

public struct BackendLearningCharacter: Codable, Sendable, Equatable {
    public let characterId: UUID
    public let roleKey: String
    public let cycleId: UUID
    public let characters: Int
    public let threshold: Int
    public let revision: Int
    public let activeAttemptId: UUID?
    public let level: String
    public let availableUnits: Int
    public let generationStatus: String?
}

extension BackendClient {
    public func learningCharacter(_ characterID: UUID) async throws -> BackendLearningCharacter {
        try await get("/v1/learning/characters/\(characterID.uuidString.lowercased())")
    }
}

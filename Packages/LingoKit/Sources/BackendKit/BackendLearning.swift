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

extension BackendClient: LearningServing {
    private struct Request: Encodable, Sendable { let requestId: UUID; var expectedRevision: Int?; var skipRemaining: Bool? }
    public func learningJourney() async throws -> LearningJourney { try await get("/v1/learning/journey") }
    public func learningHistory(_ characterID: UUID, cursor: String? = nil) async throws -> LearningHistory {
        try await get("/v1/learning/characters/\(characterID.uuidString.lowercased())/history",
                      queryItems: cursor.map { [URLQueryItem(name: "cursor", value: $0)] } ?? [])
    }
    public func startLearning(_ characterID: UUID, requestID: UUID) async throws -> LearningStart {
        try await send(path: "/v1/learning/characters/\(characterID.uuidString.lowercased())/attempts", method: "POST", body: Request(requestId: requestID))
    }
    public func learningAttempt(_ id: UUID) async throws -> LearningAttempt {
        try await get("/v1/learning/attempts/\(id.uuidString.lowercased())")
    }
    public func answerLearning(_ id: UUID, command: LearningAnswerCommand) async throws -> LearningAnswerReceipt {
        try await send(path: "/v1/learning/attempts/\(id.uuidString.lowercased())/answers", method: "POST", body: command)
    }
    public func finishLearning(_ attempt: LearningAttempt, requestID: UUID, skipRemaining: Bool) async throws -> LearningAttempt {
        try await send(path: "/v1/learning/attempts/\(attempt.id.uuidString.lowercased())/finish", method: "POST",
                       body: Request(requestId: requestID, expectedRevision: attempt.revision, skipRemaining: skipRemaining))
    }
    public func retryLearning(_ attempt: LearningAttempt, requestID: UUID) async throws -> LearningAttempt {
        try await send(path: "/v1/learning/attempts/\(attempt.id.uuidString.lowercased())/retries", method: "POST",
                       body: Request(requestId: requestID, expectedRevision: attempt.revision))
    }
}

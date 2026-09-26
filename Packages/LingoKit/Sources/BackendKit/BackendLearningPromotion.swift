import Foundation

public struct LearningPromotionEligibility: Codable, Sendable, Hashable {
    public struct Goal: Codable, Sendable, Hashable, Identifiable {
        public let id: String
        public let title: String
        public let minimumCorrect: Int
        public let minimumUnits: Int
        public let correct: Int
        public let units: Int
        public let complete: Bool
    }
    public struct Blocker: Codable, Sendable, Hashable, Identifiable {
        public let code: String
        public let message: String
        public var id: String { code }
    }
    public let level: String
    public let nextLevel: String?
    public let points: Int
    public let targetPoints: Int
    public let goals: [Goal]
    public let transferCompleted: Bool
    public let courseVersion: Int?
    public let courseHash: String?
    public let ready: Bool
    public let completedPromotionId: UUID?
    public let activePromotionId: UUID?
    public let blockers: [Blocker]
}
public struct LearningPromotion: Codable, Sendable, Hashable, Identifiable {
    public struct Beat: Codable, Sendable, Hashable, Identifiable {
        public let id: String
        public let speaker: String
        public let text: String
        public let translation: String
    }
    public struct Story: Codable, Sendable, Hashable {
        public let id: String
        public let title: String
        public let beats: [Beat]
    }
    public let id: UUID
    public let fromLevel: String
    public let toLevel: String
    public let status: String
    public let story: Story
    public let courseHash: String
    public let acknowledgedBeats: Int
    public let revision: Int
    public let profileVersion: Int
    public let completedProfileVersion: Int?
    public let completedAt: String?
    public var isCompleted: Bool { status == "completed" }
    public var currentBeat: Beat? { story.beats.indices.contains(acknowledgedBeats) ? story.beats[acknowledgedBeats] : nil }
}
public struct LearningPromotionCommand: Codable, Sendable, Hashable {
    public let requestId: UUID
    public let expectedRevision: Int
    public let expectedProfileVersion: Int
    public let confirmed: Bool
    public init(requestID: UUID, promotion: LearningPromotion) {
        requestId = requestID; expectedRevision = promotion.revision
        expectedProfileVersion = promotion.profileVersion; confirmed = true
    }
}
public protocol LearningPromotionServing: Sendable {
    func beginLearningPromotion(level: String, requestID: UUID) async throws -> LearningPromotion
    func learningPromotion(_ id: UUID) async throws -> LearningPromotion
    func advanceLearningPromotion(_ promotion: LearningPromotion, requestID: UUID) async throws -> LearningPromotion
    func completeLearningPromotion(_ id: UUID, command: LearningPromotionCommand) async throws -> LearningPromotion
}
extension BackendClient: LearningPromotionServing {
    private struct StartPromotion: Encodable, Sendable { let level: String; let requestId: UUID }
    private struct AdvancePromotion: Encodable, Sendable { let requestId: UUID; let expectedRevision: Int }
    public func beginLearningPromotion(level: String, requestID: UUID) async throws -> LearningPromotion {
        try await send(path: "/v1/learning/promotions", method: "POST", body: StartPromotion(level: level, requestId: requestID))
    }
    public func learningPromotion(_ id: UUID) async throws -> LearningPromotion {
        try await get("/v1/learning/promotions/\(id.uuidString.lowercased())")
    }
    public func advanceLearningPromotion(_ promotion: LearningPromotion, requestID: UUID) async throws -> LearningPromotion {
        try await send(path: "/v1/learning/promotions/\(promotion.id.uuidString.lowercased())/advance", method: "POST", body: AdvancePromotion(requestId: requestID, expectedRevision: promotion.revision))
    }
    public func completeLearningPromotion(_ id: UUID, command: LearningPromotionCommand) async throws -> LearningPromotion {
        try await send(path: "/v1/learning/promotions/\(id.uuidString.lowercased())/complete", method: "POST", body: command)
    }
}

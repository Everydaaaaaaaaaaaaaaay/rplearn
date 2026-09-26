import Foundation

public struct LearningOption: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let text: String
    public let imageAssetId: String?
}
public struct LearningQuestion: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable { case choice, listeningChoice, arrange, completion, dictation, matching }
    public struct Audio: Codable, Sendable, Equatable { public let assetId: String }
    public let id: String
    public let type: Kind
    public let goalId: String
    public let instruction: String
    public let prompt: String
    public let hint: String
    public let options: [LearningOption]?
    public let tokens: [LearningOption]?
    public let left: [LearningOption]?
    public let right: [LearningOption]?
    public let audio: Audio?
}
public struct LearningBeat: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let afterQuestion: Int
    public let speaker: String
    public let text: String
    public let translation: String
}
public struct LearningUnit: Codable, Sendable, Equatable {
    public let id: String
    public let version: Int
    public let schemaVersion: Int
    public let roleKey: String
    public let level: String
    public let title: String
    public let summary: String
    public let scene: String
    public let estimatedMinutes: Int
    public let goalIds: [String]
    public let beats: [LearningBeat]
    public let questions: [LearningQuestion]
}
/// 与服务端提交合同一致；客户端不包含未答题目的判题资料。
public struct LearningAnswer: Codable, Sendable, Equatable {
    public struct Pair: Codable, Sendable, Equatable {
        public let left: String
        public let right: String
        public init(left: String, right: String) { self.left = left; self.right = right }
    }
    public enum Kind: String, Codable, Sendable { case choice, arrange, text, matching, skip }
    public let kind: Kind
    public let optionId: String?
    public let tokenIds: [String]?
    public let text: String?
    public let pairs: [Pair]?
    private init(kind: Kind, optionId: String? = nil, tokenIds: [String]? = nil, text: String? = nil, pairs: [Pair]? = nil) {
        self.kind = kind; self.optionId = optionId; self.tokenIds = tokenIds; self.text = text; self.pairs = pairs
    }
    public static func choice(_ id: String) -> Self { .init(kind: .choice, optionId: id) }
    public static func arrange(_ ids: [String]) -> Self { .init(kind: .arrange, tokenIds: ids) }
    public static func text(_ text: String) -> Self { .init(kind: .text, text: text) }
    public static func matching(_ pairs: [Pair]) -> Self { .init(kind: .matching, pairs: pairs) }
    public static var skip: Self { .init(kind: .skip) }
}
public struct LearningGrade: Codable, Sendable, Equatable {
    public enum Outcome: String, Codable, Sendable { case correct, incorrect, skipped }
    public let outcome: Outcome
    public let explanation: String
    public let solution: LearningAnswer
}
public struct LearningAttempt: Codable, Sendable, Equatable, Identifiable {
    public struct Submission: Codable, Sendable, Equatable {
        public let questionId: String
        public let answer: LearningAnswer
        public let result: LearningGrade
    }
    public struct Round: Codable, Sendable, Equatable {
        public let id: UUID
        public let ordinal: Int
        public let questionIds: [String]
        public let completed: Bool
        public let answers: [Submission]
    }
    public let id: UUID
    public let characterId: UUID
    public let level: String
    public let revision: Int
    public let startedAt: String
    public let firstCompletedAt: String?
    public let unit: LearningUnit
    public let correctQuestionIds: [String]
    public let round: Round
    public var remainingCount: Int { max(0, unit.questions.count - correctQuestionIds.count) }
}
public struct LearningLevelProgress: Codable, Sendable, Equatable {
    public let publishedUnitCount: Int?
    public let level: String
    public let points: Int
    public let displayPoints: Int
    public let targetPoints: Int
    public let stars: Int
    public let currentStarPoints: Int
    public let pointsPerStar: Int
}
public struct LearningJourney: Codable, Sendable, Equatable {
    public struct Policy: Codable, Sendable, Equatable {
        public let version: Int
        public let characterThreshold: Int
        public let pointsPerQuestion: Int
        public let pointsPerStar: Int
        public let starsPerLevel: Int
    }
    public let currentLevel: String
    public let policy: Policy
    public let levels: [LearningLevelProgress]
    public var current: LearningLevelProgress? { levels.first { $0.level == currentLevel } }
}
public struct LearningHistory: Codable, Sendable, Equatable {
    public struct Item: Codable, Sendable, Equatable, Identifiable {
        public let id: UUID
        public let title: String
        public let level: String
        public let startedAt: String
        public let firstCompletedAt: String?
        public let correctCount: Int
        public let questionCount: Int
    }
    public let items: [Item]
    public let nextCursor: String?
}
public struct LearningStart: Codable, Sendable {
    public let status: String
    public let attempt: LearningAttempt?
}
public struct LearningAnswerReceipt: Codable, Sendable {
    public let result: LearningGrade
    public let awardedPoints: Int
    public let attempt: LearningAttempt
    public let progress: [LearningLevelProgress]
}
public struct LearningAnswerCommand: Encodable, Sendable {
    public let requestId: UUID
    public let roundId: UUID
    public let questionId: String
    public let expectedRevision: Int
    public let answer: LearningAnswer
    public init(requestId: UUID, attempt: LearningAttempt, questionId: String, answer: LearningAnswer) {
        self.requestId = requestId; self.roundId = attempt.round.id; self.expectedRevision = attempt.revision
        self.questionId = questionId; self.answer = answer
    }
}
public protocol LearningServing: Sendable {
    func learningAudio(_ attemptID: UUID, questionID: String, assetID: String) async throws -> Data
    func learningCharacter(_ characterID: UUID) async throws -> BackendLearningCharacter
    func learningJourney() async throws -> LearningJourney
    func learningHistory(_ characterID: UUID, cursor: String?) async throws -> LearningHistory
    func startLearning(_ characterID: UUID, requestID: UUID) async throws -> LearningStart
    func learningAttempt(_ id: UUID) async throws -> LearningAttempt
    func answerLearning(_ id: UUID, command: LearningAnswerCommand) async throws -> LearningAnswerReceipt
    func finishLearning(_ attempt: LearningAttempt, requestID: UUID, skipRemaining: Bool) async throws -> LearningAttempt
    func retryLearning(_ attempt: LearningAttempt, requestID: UUID) async throws -> LearningAttempt
}

extension LearningServing {
    public func learningAudio(_ attemptID: UUID, questionID: String, assetID: String) async throws -> Data {
        throw BackendClientError.api(code: "LEARNING_AUDIO_NOT_READY", message: "听力素材暂不可用，请稍后重试。", requestID: nil, status: 503)
    }
}

struct LearningAudioDownload: Decodable, Sendable {
    let assetId: String
    let sha256: String
    let byteSize: Int
    let durationMs: Int
    let contentType: String
    let url: URL
    let expiresAt: String
}

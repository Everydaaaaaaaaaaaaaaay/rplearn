import Foundation

public struct LearningOption: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let text: String
    public let imageAssetId: String?
    public let caption: String?
}
public struct LearningQuestion: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable { case choice, listeningChoice, audioChoice, audioMatching, arrange, audioArrange, completion, dictation, listeningCompletion, matching, cloze }
    public struct Audio: Codable, Sendable, Equatable { public let assetId: String }
    public struct AudioOption: Codable, Sendable, Equatable, Identifiable { public let id: String; public let audio: Audio }
    public let id: String
    public let type: Kind
    public let goalId: String
    public let instruction: String
    public let prompt: String
    public let hint: String
    public let material: String?
    public struct MaterialImage: Codable, Sendable, Equatable { public let assetId: String; public let label: String }
    public let materialImages: [MaterialImage]?
    public let options: [LearningOption]?
    public let tokens: [LearningOption]?
    public let left: [LearningOption]?
    public let right: [LearningOption]?
    public let audio: Audio?
    public let audioOptions: [AudioOption]?
    public var audioAssetIDs: [String] { audio.map { [$0.assetId] } ?? (audioOptions ?? []).map(\.audio.assetId) }
    public let passage: String?
    public let wordLimit: Int?
    /// 与服务端相同的空白分词规则；连字符及撇号不拆词。
    public static func answerWordCount(_ text: String) -> Int {
        text.unicodeScalars.split { scalar in
            switch scalar.value {
            case 0x0009...0x000D, 0x0020, 0x00A0, 0x1680, 0x2000...0x200A,
                 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF: true
            default: false
            }
        }.count
    }
    public var clozeSlotIDs: [String] {
        guard let passage, let pattern = try? NSRegularExpression(pattern: #"\{([a-z][a-z0-9_.-]{0,119})\}"#) else { return [] }
        let text = passage as NSString
        return pattern.matches(in: passage, range: NSRange(location: 0, length: text.length)).map { text.substring(with: $0.range(at: 1)) }
    }
    public var imageAssetIDs: [String] {
        let candidates: [LearningOption]
        switch type {
        case .choice, .listeningChoice: candidates = options ?? []
        case .audioMatching: candidates = right ?? []
        case .matching: candidates = (left ?? []) + (right ?? [])
        default: candidates = []
        }
        return Array(Set(candidates.compactMap(\.imageAssetId) + (materialImages ?? []).map(\.assetId))).sorted()
    }
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
    public struct OriginalGroup: Codable, Sendable, Equatable { public let id: String; public let family: String; public let label: String }
    public let originalGroup: OriginalGroup?
    public let beats: [LearningBeat]
    public let questions: [LearningQuestion]
}
/// 与服务端提交合同一致；客户端不包含未答题目的判题资料。
public struct LearningAnswer: Codable, Sendable, Equatable {
    public struct Fill: Codable, Sendable, Equatable {
        public let slotId: String
        public let tokenId: String
        public init(slotId: String, tokenId: String) { self.slotId = slotId; self.tokenId = tokenId }
    }
    public struct Pair: Codable, Sendable, Equatable {
        public let left: String
        public let right: String
        public init(left: String, right: String) { self.left = left; self.right = right }
    }
    public enum Kind: String, Codable, Sendable { case choice, arrange, text, matching, cloze, skip }
    public let kind: Kind
    public let optionId: String?
    public let tokenIds: [String]?
    public let text: String?
    public let pairs: [Pair]?
    public let fills: [Fill]?
    private init(kind: Kind, optionId: String? = nil, tokenIds: [String]? = nil, text: String? = nil, pairs: [Pair]? = nil, fills: [Fill]? = nil) {
        self.kind = kind; self.optionId = optionId; self.tokenIds = tokenIds; self.text = text; self.pairs = pairs
        self.fills = fills
    }
    public static func choice(_ id: String) -> Self { .init(kind: .choice, optionId: id) }
    public static func arrange(_ ids: [String]) -> Self { .init(kind: .arrange, tokenIds: ids) }
    public static func text(_ text: String) -> Self { .init(kind: .text, text: text) }
    public static func matching(_ pairs: [Pair]) -> Self { .init(kind: .matching, pairs: pairs) }
    public static func cloze(_ fills: [Fill]) -> Self { .init(kind: .cloze, fills: fills) }
    public static var skip: Self { .init(kind: .skip) }
}
public struct LearningGrade: Codable, Sendable, Equatable {
    public struct PairResult: Codable, Sendable, Equatable {
        public let left: String
        public let correct: Bool
    }
    public let pairResults: [PairResult]?
    public struct SlotResult: Codable, Sendable, Equatable {
        public let slotId: String
        public let correct: Bool
    }
    public enum Outcome: String, Codable, Sendable { case correct, incorrect, skipped }
    public let outcome: Outcome
    public let explanation: String
    public let solution: LearningAnswer
    public let slotResults: [SlotResult]?
}
public struct LearningAttempt: Codable, Sendable, Equatable, Identifiable {
    public struct Submission: Codable, Sendable, Equatable {
        public let questionId: String
        public let answer: LearningAnswer
        public let result: LearningGrade
        /// Authoritative reward for this answer; older cached receipts may omit it.
        public let awardedPoints: Int?
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
    public let promotion: LearningPromotionEligibility?
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
public struct LearningAnswerCommand: Codable, Sendable {
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
public struct LearningSpeechScript: Codable, Sendable, Equatable {
    public struct Segment: Codable, Sendable, Equatable {
        public let text: String
        public let pauseAfterMs: Int
        public init(text: String, pauseAfterMs: Int = 0) { self.text = text; self.pauseAfterMs = pauseAfterMs }
    }
    public let assetId: String
    public let segments: [Segment]
    public init(assetId: String, segments: [Segment]) { self.assetId = assetId; self.segments = segments }
}

public protocol LearningServing: Sendable {
    func learningOriginals(level: String) async throws -> LearningOriginalCatalog
    func startOriginalLearning(_ characterID: UUID, unitID: String, requestID: UUID) async throws -> LearningStart
    func learningImage(_ attemptID: UUID, questionID: String, assetID: String) async throws -> Data
    func learningSpeech(_ attemptID: UUID, questionID: String, assetID: String) async throws -> LearningSpeechScript
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

public struct LearningOriginalCatalog: Codable, Sendable, Equatable {
    public struct Unit: Codable, Sendable, Equatable, Identifiable { public let id: String; public let title: String; public let family: String; public let label: String; public let questions: Int }
    public let units: [Unit]
}

extension LearningServing {
    public func learningSpeech(_ attemptID: UUID, questionID: String, assetID: String) async throws -> LearningSpeechScript {
        throw BackendClientError.api(code: "LEARNING_AUDIO_NOT_READY", message: "听力脚本暂不可用，请稍后重试。", requestID: nil, status: 503)
    }

    public func learningOriginals(level: String) async throws -> LearningOriginalCatalog { .init(units: []) }
    public func startOriginalLearning(_ characterID: UUID, unitID: String, requestID: UUID) async throws -> LearningStart { throw BackendClientError.invalidResponse }

    public func learningImage(_ attemptID: UUID, questionID: String, assetID: String) async throws -> Data {
        throw BackendClientError.api(code: "LEARNING_IMAGE_NOT_READY", message: "图片素材暂不可用，请稍后重试。", requestID: nil, status: 503)
    }

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

struct LearningImageDownload: Decodable, Sendable {
    let assetId: String
    let sha256: String
    let byteSize: Int
    let width: Int
    let height: Int
    let contentType: String
    let url: URL
    let expiresAt: String
}

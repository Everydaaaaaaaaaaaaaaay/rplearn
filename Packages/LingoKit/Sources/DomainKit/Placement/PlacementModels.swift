import Foundation
import PersistenceKit

public enum PlacementSkill: String, Codable, CaseIterable, Sendable {
    case vocabulary
    case grammar
    case reading
    case listening

    public var displayName: String {
        switch self {
        case .vocabulary: "词汇"
        case .grammar: "语法与用法"
        case .reading: "阅读理解"
        case .listening: "听力理解"
        }
    }
}

/// 听力题的重听次数策略。每道题独立计数，切换题目后重置。
public enum PlacementListeningPolicy {
    public static let maximumPlayCount = 2

    public static func canPlay(currentCount: Int) -> Bool {
        currentCount < maximumPlayCount
    }

    public static func remainingPlayCount(after currentCount: Int) -> Int {
        max(0, maximumPlayCount - max(0, currentCount))
    }
}

/// 同一能力使用多种任务形态，避免短测退化成单一的“选词填空”。
public enum PlacementQuestionFormat: String, Codable, CaseIterable, Sendable {
    case wordMeaning
    case wordInContext
    case grammarForm
    case grammarInContext
    case noticeReading
    case readingDetail
    case readingMainIdea
    case readingInference
    case listeningDetail
    case listeningMainIdea
    case listeningInference

    public var displayName: String {
        switch self {
        case .wordMeaning: "词义辨析"
        case .wordInContext: "语境选词"
        case .grammarForm: "语法形式"
        case .grammarInContext: "语境用法"
        case .noticeReading: "实用阅读"
        case .readingDetail: "细节理解"
        case .readingMainIdea: "主旨理解"
        case .readingInference: "推断理解"
        case .listeningDetail: "听力细节"
        case .listeningMainIdea: "听力主旨"
        case .listeningInference: "听力推断"
        }
    }

    public var skill: PlacementSkill {
        switch self {
        case .wordMeaning, .wordInContext:
            .vocabulary
        case .grammarForm, .grammarInContext:
            .grammar
        case .noticeReading, .readingDetail, .readingMainIdea, .readingInference:
            .reading
        case .listeningDetail, .listeningMainIdea, .listeningInference:
            .listening
        }
    }
}

/// 题目难度与区分度采用 IRT 常见参数范围；题干与听力文本均来自项目自有题库。
public struct PlacementQuestion: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let skill: PlacementSkill
    public let format: PlacementQuestionFormat
    public let prompt: String
    public let context: String?
    public let audioText: String?
    public let audioLanguage: String?
    /// 随安装包分发的固定听力音频名；运行时禁止用 TTS 临时合成听力题。
    public let audioAssetName: String?
    public let options: [String]
    public let correctIndex: Int
    public let difficulty: Double
    public let discrimination: Double
    public let explanationZh: String

    public init(
        id: String,
        skill: PlacementSkill,
        format: PlacementQuestionFormat,
        prompt: String,
        context: String? = nil,
        audioText: String? = nil,
        audioLanguage: String? = nil,
        audioAssetName: String? = nil,
        options: [String],
        correctIndex: Int,
        difficulty: Double,
        discrimination: Double,
        explanationZh: String
    ) {
        self.id = id
        self.skill = skill
        self.format = format
        self.prompt = prompt
        self.context = context
        self.audioText = audioText
        self.audioLanguage = audioLanguage
        self.audioAssetName = audioAssetName
        self.options = options
        self.correctIndex = correctIndex
        self.difficulty = difficulty
        self.discrimination = discrimination
        self.explanationZh = explanationZh
    }
}

public enum PlacementQuestionBank {
    public enum BankError: Error, Equatable {
        case duplicateID(String)
        case insufficientQuestions(Int)
        case invalidQuestion(String)
        case missingSkill(PlacementSkill)
        case insufficientFormatDiversity(PlacementSkill)
        case insufficientDifficultyCoverage(PlacementSkill)
        case excessiveDifficultyGap(PlacementSkill)
    }

    public static func load(from url: URL) throws -> [PlacementQuestion] {
        let questions = try JSONDecoder().decode(
            [PlacementQuestion].self,
            from: Data(contentsOf: url)
        )
        try validate(questions)
        return questions
    }

    public static func validate(_ questions: [PlacementQuestion]) throws {
        guard questions.count >= 80 else {
            throw BankError.insufficientQuestions(questions.count)
        }
        var ids = Set<String>()
        for question in questions {
            guard ids.insert(question.id).inserted else {
                throw BankError.duplicateID(question.id)
            }
            guard question.options.count == 4,
                  question.options.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
                  question.options.indices.contains(question.correctIndex),
                  (-3...3).contains(question.difficulty),
                  (0.5...2).contains(question.discrimination),
                  !question.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  question.format.skill == question.skill
            else {
                throw BankError.invalidQuestion(question.id)
            }

            if question.skill == .listening {
                guard let audioText = question.audioText,
                      !audioText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      question.audioLanguage?.hasPrefix("en-") == true,
                      let audioAssetName = question.audioAssetName,
                      !audioAssetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      question.context == nil
                else {
                    throw BankError.invalidQuestion(question.id)
                }
            } else if question.audioText != nil
                        || question.audioLanguage != nil
                        || question.audioAssetName != nil {
                throw BankError.invalidQuestion(question.id)
            }

            if question.skill == .reading {
                guard let context = question.context,
                      !context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else {
                    throw BankError.invalidQuestion(question.id)
                }
            }
        }

        for skill in PlacementSkill.allCases {
            let matching = questions
                .filter { $0.skill == skill }
                .sorted { $0.difficulty < $1.difficulty }
            guard matching.count >= 20 else {
                throw BankError.missingSkill(skill)
            }
            guard Set(matching.map(\.format)).count >= 2 else {
                throw BankError.insufficientFormatDiversity(skill)
            }
            guard let easiest = matching.first?.difficulty,
                  let hardest = matching.last?.difficulty,
                  easiest <= -2.75,
                  hardest >= 2.5
            else {
                throw BankError.insufficientDifficultyCoverage(skill)
            }
            let largestGap = zip(matching, matching.dropFirst())
                .map { $1.difficulty - $0.difficulty }
                .max() ?? 0
            guard largestGap <= 0.55 else {
                throw BankError.excessiveDifficultyGap(skill)
            }
        }
    }
}

public struct PlacementResponse: Sendable, Equatable {
    public let questionID: String
    public let skill: PlacementSkill
    public let format: PlacementQuestionFormat
    public let wasCorrect: Bool
    public let difficulty: Double

    public init(
        questionID: String,
        skill: PlacementSkill,
        format: PlacementQuestionFormat,
        wasCorrect: Bool,
        difficulty: Double
    ) {
        self.questionID = questionID
        self.skill = skill
        self.format = format
        self.wasCorrect = wasCorrect
        self.difficulty = difficulty
    }
}

public struct PlacementSkillResult: Sendable, Equatable, Identifiable {
    public var id: PlacementSkill { skill }
    public let skill: PlacementSkill
    public let correct: Int
    public let total: Int

    public var accuracy: Double {
        guard total > 0 else { return 0 }
        return Double(correct) / Double(total)
    }
}

/// CEFR 仅作为能力区间参照，不代表官方考试认证结果。
public enum PlacementReferenceLevel: String, Sendable, Equatable {
    case preA1 = "Pre-A1"
    case a1 = "A1"
    case a2 = "A2"
    case b1 = "B1"
    case b2 = "B2"
    case c1 = "C1"
    case c2 = "C2"
}

public struct PlacementResult: Sendable, Equatable {
    public let ability: Double
    public let standardError: Double
    public let levelConfidence: Double
    public let score: Int
    public let scoreRange: ClosedRange<Int>
    public let difficultyLevel: DifficultyLevel
    public let referenceLevel: PlacementReferenceLevel
    public let answeredCount: Int
    public let skillResults: [PlacementSkillResult]

    public init(
        ability: Double,
        standardError: Double,
        levelConfidence: Double,
        score: Int,
        scoreRange: ClosedRange<Int>,
        difficultyLevel: DifficultyLevel,
        referenceLevel: PlacementReferenceLevel,
        answeredCount: Int,
        skillResults: [PlacementSkillResult]
    ) {
        self.ability = ability
        self.standardError = standardError
        self.levelConfidence = levelConfidence
        self.score = score
        self.scoreRange = scoreRange
        self.difficultyLevel = difficultyLevel
        self.referenceLevel = referenceLevel
        self.answeredCount = answeredCount
        self.skillResults = skillResults
    }

    public var confidenceLabel: String {
        switch levelConfidence {
        case 0.68...: "高"
        case 0.52...: "较高"
        default: "有限"
        }
    }
}

import Foundation
import PersistenceKit

public enum PlacementSkill: String, Codable, CaseIterable, Sendable {
    case vocabulary
    case grammar
    case reading

    public var displayName: String {
        switch self {
        case .vocabulary: "词汇"
        case .grammar: "语法与用法"
        case .reading: "阅读理解"
        }
    }
}

/// 题目难度与区分度采用 IRT 常见参数范围；题干均来自项目自有题库。
public struct PlacementQuestion: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let skill: PlacementSkill
    public let prompt: String
    public let context: String?
    public let options: [String]
    public let correctIndex: Int
    public let difficulty: Double
    public let discrimination: Double
    public let explanationZh: String

    public init(
        id: String,
        skill: PlacementSkill,
        prompt: String,
        context: String? = nil,
        options: [String],
        correctIndex: Int,
        difficulty: Double,
        discrimination: Double,
        explanationZh: String
    ) {
        self.id = id
        self.skill = skill
        self.prompt = prompt
        self.context = context
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
        guard questions.count >= 24 else {
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
                  !question.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                throw BankError.invalidQuestion(question.id)
            }
        }
        for skill in PlacementSkill.allCases
            where questions.filter({ $0.skill == skill }).count < 6
        {
            throw BankError.missingSkill(skill)
        }
    }
}

public struct PlacementResponse: Sendable, Equatable {
    public let questionID: String
    public let skill: PlacementSkill
    public let wasCorrect: Bool
    public let difficulty: Double

    public init(
        questionID: String,
        skill: PlacementSkill,
        wasCorrect: Bool,
        difficulty: Double
    ) {
        self.questionID = questionID
        self.skill = skill
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

public struct PlacementResult: Sendable, Equatable {
    public let ability: Double
    public let standardError: Double
    public let score: Int
    public let scoreRange: ClosedRange<Int>
    public let difficultyLevel: DifficultyLevel
    public let answeredCount: Int
    public let skillResults: [PlacementSkillResult]

    public init(
        ability: Double,
        standardError: Double,
        score: Int,
        scoreRange: ClosedRange<Int>,
        difficultyLevel: DifficultyLevel,
        answeredCount: Int,
        skillResults: [PlacementSkillResult]
    ) {
        self.ability = ability
        self.standardError = standardError
        self.score = score
        self.scoreRange = scoreRange
        self.difficultyLevel = difficultyLevel
        self.answeredCount = answeredCount
        self.skillResults = skillResults
    }
}

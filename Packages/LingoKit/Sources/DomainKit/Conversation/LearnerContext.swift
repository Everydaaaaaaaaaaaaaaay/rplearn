import Foundation
import PersistenceKit

/// 每次生成消息时使用的学习者上下文。它来自用户档案，不依赖某个角色的历史难度字段。
public struct LearnerContext: Sendable, Equatable {
    public let nickname: String?
    public let difficulty: DifficultyLevel
    public let goal: LearningGoal
    public let studyStage: StudyStage?

    public init(
        nickname: String? = nil,
        difficulty: DifficultyLevel,
        goal: LearningGoal = .dailyConversation,
        studyStage: StudyStage? = nil
    ) {
        let compactNickname = nickname?
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let normalizedNickname = compactNickname.map { String($0.prefix(40)) }
        self.nickname = normalizedNickname?.isEmpty == false ? normalizedNickname : nil
        self.difficulty = difficulty
        self.goal = goal
        self.studyStage = studyStage
    }

    public init(profile: UserProfileDTO) {
        self.init(
            nickname: profile.displayName,
            difficulty: profile.difficultyLevel,
            goal: profile.learningGoal,
            studyStage: profile.studyStage
        )
    }

    public static func fallback(difficulty: DifficultyLevel) -> Self {
        Self(difficulty: difficulty)
    }
}

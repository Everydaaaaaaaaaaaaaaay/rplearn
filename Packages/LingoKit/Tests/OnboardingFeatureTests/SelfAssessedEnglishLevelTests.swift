import OnboardingFeature
import PersistenceKit
import Testing

@Suite("自评英语等级")
struct SelfAssessedEnglishLevelTests {
    @Test("六档描述映射到由浅入深的代表等级")
    func mapsToRepresentativeDifficultyLevels() {
        #expect(SelfAssessedEnglishLevel.starting.difficultyLevel == .primary3)
        #expect(SelfAssessedEnglishLevel.foundation.difficultyLevel == .primary6)
        #expect(SelfAssessedEnglishLevel.everyday.difficultyLevel == .junior3)
        #expect(SelfAssessedEnglishLevel.independent.difficultyLevel == .senior3)
        #expect(SelfAssessedEnglishLevel.confident.difficultyLevel == .undergraduate)
        #expect(SelfAssessedEnglishLevel.advanced.difficultyLevel == .advanced)
    }

    @Test("已有细分等级可稳定回显到自评档位", arguments: DifficultyLevel.allCases)
    func restoresExistingDifficulty(_ difficulty: DifficultyLevel) {
        let selfAssessment = SelfAssessedEnglishLevel.closest(to: difficulty)
        switch difficulty {
        case .primary1, .primary2, .primary3:
            #expect(selfAssessment == .starting)
        case .primary4, .primary5, .primary6:
            #expect(selfAssessment == .foundation)
        case .junior1, .junior2, .junior3:
            #expect(selfAssessment == .everyday)
        case .senior1, .senior2, .senior3:
            #expect(selfAssessment == .independent)
        case .undergraduate:
            #expect(selfAssessment == .confident)
        case .postgraduate, .advanced:
            #expect(selfAssessment == .advanced)
        }
    }
}

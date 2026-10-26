import Testing
@testable import LearningFeature

@Suite("Learning history accuracy")
struct LearningHistoryPresentationTests {
    @Test("70 percent is green, 50 percent is yellow, lower values are red")
    func boundaries() {
        #expect(LearningAccuracyBand(correct: 7, total: 10) == .high)
        #expect(LearningAccuracyBand(correct: 10, total: 10) == .high)
        #expect(LearningAccuracyBand(correct: 5, total: 10) == .medium)
        #expect(LearningAccuracyBand(correct: 69, total: 100) == .medium)
        #expect(LearningAccuracyBand(correct: 49, total: 100) == .low)
        #expect(LearningAccuracyBand(correct: 0, total: 15) == .low)
        #expect(LearningAccuracyBand(correct: 2, total: 3) == .medium)
        #expect(LearningAccuracyBand(correct: 0, total: 0) == .low)
    }
}

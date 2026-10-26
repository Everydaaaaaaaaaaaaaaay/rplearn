import Testing
import BackendKit
import Foundation
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

    @Test("Chat percentage clamps invalid and excess values without premature unlock")
    func chatPercentage() {
        #expect(learningChatPercentage(characters: 280, threshold: 500) == 56)
        #expect(learningChatPercentage(characters: 290, threshold: 500) == 58)
        #expect(learningChatPercentage(characters: 499, threshold: 500) == 99)
        #expect(learningChatPercentage(characters: 500, threshold: 500) == 100)
        #expect(learningChatPercentage(characters: 700, threshold: 500) == 100)
        #expect(learningChatPercentage(characters: -1, threshold: 500) == 0)
        #expect(learningChatPercentage(characters: 0, threshold: 0) == 0)
    }

    @Test("Accuracy filtering uses the same inclusive boundaries as the displayed colors")
    func accuracyFilters() {
        for correct in 0...100 {
            let selected = LearningHistoryAccuracyFilter.allCases.filter { $0 != .all && $0.matches(correct: correct, total: 100) }
            #expect(selected.count == 1)
            #expect(selected.first == (correct >= 70 ? .high : correct >= 50 ? .medium : .low))
            #expect(LearningHistoryAccuracyFilter.all.matches(correct: correct, total: 100))
        }
    }

    @Test("Pending and accuracy filters compose, distinguish ongoing rounds and reset cleanly")
    func composedFilters() throws {
        let ongoing = try historyItem(correct: 2, total: 6, completed: false)
        let retry = try historyItem(correct: 4, total: 6, completed: true)
        let complete = try historyItem(correct: 6, total: 6, completed: true)
        let highRetry = try historyItem(correct: 7, total: 10, completed: true)
        var filter = LearningHistoryFilter()
        #expect(!filter.isActive && filter.summary.isEmpty)
        #expect(filter.matches(ongoing) && filter.matches(retry) && filter.matches(complete))
        filter.onlyUnfinished = true
        #expect(filter.summary == "待补答")
        #expect(!filter.matches(ongoing) && filter.matches(retry) && !filter.matches(complete))
        filter.accuracy = .medium
        #expect(filter.summary == "待补答 · 50%–<70%")
        #expect(filter.matches(retry) && !filter.matches(highRetry))
        filter.accuracy = .high
        #expect(filter.matches(highRetry) && !filter.matches(complete))
        filter.onlyUnfinished = false
        #expect(filter.matches(complete) && filter.matches(highRetry))
        filter = LearningHistoryFilter()
        #expect(!filter.isActive && filter.summary.isEmpty)
    }

    private func historyItem(correct: Int, total: Int, completed: Bool) throws -> LearningHistory.Item {
        let data = try JSONSerialization.data(withJSONObject: [
            "id": UUID().uuidString, "title": "阅读理解 · 车站问路", "level": "primary3",
            "startedAt": "2026-10-26T01:00:00Z", "correctCount": correct, "questionCount": total,
            "firstCompletedAt": completed ? "2026-10-26T01:05:00Z" : NSNull()
        ])
        return try JSONDecoder().decode(LearningHistory.Item.self, from: data)
    }
}

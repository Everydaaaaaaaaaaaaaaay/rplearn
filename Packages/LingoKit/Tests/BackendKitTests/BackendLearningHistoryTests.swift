import Foundation
import Testing
@testable import BackendKit

@Suite("Challenge history rewards")
struct BackendLearningHistoryTests {
    @Test("History keeps actual awarded points separate from correct answers and preserves unknown legacy totals")
    func earnedPointsContract() throws {
        let data = Data(#"{"items":[{"id":"20000000-0000-4000-8000-000000000001","title":"New practice","level":"senior3","startedAt":"2026-10-26T00:00:00.000Z","correctCount":4,"questionCount":10,"earnedPoints":3},{"id":"20000000-0000-4000-8000-000000000002","title":"Repeated practice","level":"senior3","startedAt":"2026-10-25T00:00:00Z","correctCount":10,"questionCount":10,"earnedPoints":0},{"id":"20000000-0000-4000-8000-000000000003","title":"Legacy response","level":"senior3","startedAt":"2026-10-24T00:00:00Z","correctCount":6,"questionCount":10}],"nextCursor":"next-page"}"#.utf8)
        let history = try JSONDecoder().decode(LearningHistory.self, from: data)
        #expect(history.items.map(\.earnedPoints) == [3, 0, nil])
        #expect(history.items.map(\.correctCount) == [4, 10, 6])
        #expect(history.nextCursor == "next-page")
        #expect(try JSONDecoder().decode(LearningHistory.self, from: JSONEncoder().encode(history)) == history)
    }
}

import Foundation
import Testing
@testable import DomainKit

@Suite("主动消息节奏")
struct ProactiveMessageSchedulePolicyTests {
    @Test("随机值控制在指定的安静时长范围")
    func respectsRandomWindow() {
        let anchor = Date(timeIntervalSince1970: 1_700_000_000)
        let calendar = utcCalendar()

        let earliest = ProactiveMessageSchedulePolicy.nextDate(
            after: anchor,
            randomUnit: 0,
            minimumHours: 36,
            maximumHours: 72,
            calendar: calendar
        )
        let latest = ProactiveMessageSchedulePolicy.nextDate(
            after: anchor,
            randomUnit: 1,
            minimumHours: 36,
            maximumHours: 72,
            calendar: calendar
        )

        #expect(earliest >= anchor.addingTimeInterval(36 * 60 * 60))
        #expect(latest >= anchor.addingTimeInterval(72 * 60 * 60))
    }

    @Test("夜间时间顺延到次日上午")
    func movesNightTimeToMorning() throws {
        let calendar = utcCalendar()
        let anchor = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 27, hour: 12))
        )

        let date = ProactiveMessageSchedulePolicy.nextDate(
            after: anchor,
            randomUnit: 0,
            minimumHours: 10,
            maximumHours: 10,
            calendar: calendar
        )

        #expect(calendar.component(.day, from: date) == 28)
        #expect(calendar.component(.hour, from: date) == 10)
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}

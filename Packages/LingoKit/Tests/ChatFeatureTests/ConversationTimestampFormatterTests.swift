import Foundation
import Testing
@testable import ChatFeature

@Suite("会话列表时间显示")
struct ConversationTimestampFormatterTests {
    @Test("一分钟内显示刚刚")
    func showsJustNowWithinOneMinute() {
        #expect(formatted(secondsBeforeNow: 0) == "刚刚")
        #expect(formatted(secondsBeforeNow: 60) == "刚刚")
    }

    @Test("当天超过一分钟显示具体时间")
    func showsClockTimeForToday() {
        let messageDate = now.addingTimeInterval(-61)

        #expect(
            ConversationTimestampFormatter.string(
                for: messageDate,
                relativeTo: now,
                calendar: calendar
            ) == messageDate.formatted(date: .omitted, time: .shortened)
        )
    }

    @Test("昨天的消息显示昨天")
    func showsYesterday() {
        let messageDate = calendar.date(byAdding: .day, value: -1, to: now)!

        #expect(
            ConversationTimestampFormatter.string(
                for: messageDate,
                relativeTo: now,
                calendar: calendar
            ) == "昨天"
        )
    }

    @Test("前天及更早的消息直接显示月日")
    func showsMonthAndDayBeforeYesterday() {
        let messageDate = calendar.date(byAdding: .day, value: -2, to: now)!

        #expect(
            ConversationTimestampFormatter.string(
                for: messageDate,
                relativeTo: now,
                calendar: calendar
            ) == messageDate.formatted(.dateTime.month().day())
        )
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)!
        return calendar
    }

    private var now: Date {
        calendar.date(
            from: DateComponents(
                year: 2026,
                month: 8,
                day: 29,
                hour: 14,
                minute: 30
            )
        )!
    }

    private func formatted(secondsBeforeNow seconds: TimeInterval) -> String {
        ConversationTimestampFormatter.string(
            for: now.addingTimeInterval(-seconds),
            relativeTo: now,
            calendar: calendar
        )
    }
}

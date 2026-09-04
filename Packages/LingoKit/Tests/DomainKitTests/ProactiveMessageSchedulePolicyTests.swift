import Foundation
import Testing
@testable import DomainKit
import PersistenceKit

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

    @Test("未回复时最多只安排一次自然跟进")
    func limitsUnansweredFollowUps() {
        let start = Date(timeIntervalSince1970: 1_788_000_000)
        let introduction = message(
            role: .assistant,
            orderIndex: 0,
            createdAt: start
        )
        #expect(ProactiveMessageSchedulePolicy.shouldScheduleCheckIn(
            recentMessages: [introduction],
            hasPendingCheckIn: false
        ))
        #expect(!ProactiveMessageSchedulePolicy.shouldScheduleCheckIn(
            recentMessages: [introduction],
            hasPendingCheckIn: true
        ))

        let unansweredFollowUp = message(
            role: .assistant,
            orderIndex: 1,
            createdAt: start.addingTimeInterval(48 * 60 * 60)
        )
        #expect(!ProactiveMessageSchedulePolicy.shouldScheduleCheckIn(
            recentMessages: [introduction, unansweredFollowUp],
            hasPendingCheckIn: false
        ))
    }

    @Test("投递前要求时间线未变化且安静时长足够")
    func validatesTimelineBeforeDelivery() {
        let start = Date(timeIntervalSince1970: 1_788_000_000)
        let latest = message(role: .assistant, orderIndex: 0, createdAt: start)
        let due = start.addingTimeInterval(36 * 60 * 60)

        #expect(ProactiveMessageSchedulePolicy.shouldDeliverCheckIn(
            recentMessages: [latest],
            scheduledAfterMessageID: latest.id,
            at: due
        ))
        #expect(!ProactiveMessageSchedulePolicy.shouldDeliverCheckIn(
            recentMessages: [latest],
            scheduledAfterMessageID: UUID(),
            at: due
        ))
        #expect(!ProactiveMessageSchedulePolicy.shouldDeliverCheckIn(
            recentMessages: [latest],
            scheduledAfterMessageID: latest.id,
            at: start.addingTimeInterval(2 * 60 * 60)
        ))
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func message(
        role: MessageRole,
        orderIndex: Int,
        createdAt: Date
    ) -> MessageDTO {
        MessageDTO(
            id: UUID(),
            role: role,
            kind: .text,
            text: "message \(orderIndex)",
            orderIndex: orderIndex,
            createdAt: createdAt
        )
    }
}

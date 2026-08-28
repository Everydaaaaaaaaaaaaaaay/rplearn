import DesignSystem
import Foundation
import PersistenceKit
import Testing
@testable import ChatFeature

@Suite("Chat timeline policy")
struct ChatTimelinePolicyTests {
    @Test("首条、长间隔与跨天消息显示时间")
    func timeMarkersFollowConversationBreaks() {
        let calendar = testCalendar
        let start = date(2026, 8, 28, 10, 0, calendar: calendar)
        let messages = [
            message(role: .assistant, at: start, index: 0),
            message(role: .assistant, at: start.addingTimeInterval(60), index: 1),
            message(role: .assistant, at: start.addingTimeInterval(16 * 60), index: 2),
            message(
                role: .user,
                at: date(2026, 8, 29, 8, 0, calendar: calendar),
                index: 3
            ),
        ]

        #expect(
            messages.indices.map {
                ChatTimelinePolicy.shouldShowTimeMarker(
                    in: messages,
                    at: $0,
                    calendar: calendar
                )
            } == [true, false, true, true]
        )
    }

    @Test("同一发送者的短间隔消息形成连续气泡组")
    func consecutiveMessagesFormVisualGroup() {
        let start = Date(timeIntervalSince1970: 1_787_886_000)
        let messages = [
            message(role: .assistant, at: start, index: 0),
            message(role: .assistant, at: start.addingTimeInterval(30), index: 1),
            message(role: .assistant, at: start.addingTimeInterval(60), index: 2),
            message(role: .user, at: start.addingTimeInterval(70), index: 3),
        ]

        #expect(ChatTimelinePolicy.groupPosition(in: messages, at: 0) == .first)
        #expect(ChatTimelinePolicy.groupPosition(in: messages, at: 1) == .middle)
        #expect(ChatTimelinePolicy.groupPosition(in: messages, at: 2) == .last)
        #expect(ChatTimelinePolicy.groupPosition(in: messages, at: 3) == .single)
        #expect(ChatTimelinePolicy.showsIncomingAvatar(
            in: messages,
            at: 0,
            hasTypingContinuation: false
        ) == false)
        #expect(ChatTimelinePolicy.showsIncomingAvatar(
            in: messages,
            at: 2,
            hasTypingContinuation: false
        ))
        #expect(ChatTimelinePolicy.showsOutgoingAvatar(in: messages, at: 3))
    }

    @Test("最近一条用户消息展示送达并在回复开始后变为已读")
    func receiptTracksLatestOutgoingMessage() {
        let start = Date(timeIntervalSince1970: 1_787_886_000)
        let userMessage = message(role: .user, at: start, index: 0)

        #expect(ChatTimelinePolicy.deliveryReceipt(
            in: [userMessage],
            at: 0,
            isReplying: false
        ) == .delivered)
        #expect(ChatTimelinePolicy.deliveryReceipt(
            in: [userMessage],
            at: 0,
            isReplying: true
        ) == .read)

        let reply = message(role: .assistant, at: start.addingTimeInterval(20), index: 1)
        #expect(ChatTimelinePolicy.deliveryReceipt(
            in: [userMessage, reply],
            at: 0,
            isReplying: false
        ) == .read)
    }

    @Test("中文时间文案区分今天和昨天")
    func localizedTimeMarkersAreHumanReadable() {
        let calendar = testCalendar
        let now = date(2026, 8, 28, 20, 0, calendar: calendar)
        let today = date(2026, 8, 28, 10, 5, calendar: calendar)
        let yesterday = date(2026, 8, 27, 22, 8, calendar: calendar)

        let todayText = ChatTimelinePolicy.timeMarkerText(
            for: today,
            relativeTo: now,
            calendar: calendar
        )
        let yesterdayText = ChatTimelinePolicy.timeMarkerText(
            for: yesterday,
            relativeTo: now,
            calendar: calendar
        )

        #expect(todayText.hasPrefix("今天 "))
        #expect(todayText.contains("10:05"))
        #expect(yesterdayText.hasPrefix("昨天 "))
        #expect(yesterdayText.contains("22:08"))
    }

    private var testCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)!
        calendar.locale = Locale(identifier: "zh_CN")
        return calendar
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }

    private func message(role: MessageRole, at date: Date, index: Int) -> MessageDTO {
        MessageDTO(
            id: UUID(),
            role: role,
            kind: .text,
            text: "message \(index)",
            orderIndex: index,
            createdAt: date
        )
    }
}

import DomainKit
import Foundation
import Testing
@testable import ChatFeature

@Suite("聊天顶部状态文案")
struct ChatHeaderStatusTests {
    /// 2026-09-17 12:19 北京时间 = 墨尔本 14:19。
    private let now = Date(timeIntervalSince1970: 1_789_618_740)
    private let melbourne = "Australia/Melbourne"

    private func text(
        _ state: NPCPresenceState,
        lastActiveAt: Date? = nil,
        isStreaming: Bool = false
    ) -> String {
        ChatHeaderStatus.text(
            presence: NPCPresenceSnapshot(
                state: state,
                lastActiveAt: lastActiveAt,
                timeZoneIdentifier: melbourne
            ),
            at: now,
            isStreaming: isStreaming
        )
    }

    @Test("在线状态不再占用顶部显示城市时钟")
    func compactPresence() {
        #expect(text(.online) == "在线")
        #expect(text(.recentlyActive) == "刚刚在线")
        #expect(text(.offline) == "离线")
        #expect(text(.online, isStreaming: true) == "正在输入")
    }

    @Test("离线状态完整保留角色时区的最后在线时间")
    func offlineKeepsLastActive() {
        #expect(text(.offline, lastActiveAt: now.addingTimeInterval(-2 * 60 * 60)) == "12:19在线过")
        #expect(text(.offline, lastActiveAt: now.addingTimeInterval(-25 * 60 * 60)) == "昨天13:19在线")
        #expect(text(.offline, lastActiveAt: now.addingTimeInterval(-5 * 24 * 60 * 60)) == "9/12 14:19在线")
    }

    @Test("独立时钟正确显示城市当地时间和日期，包括跨日与夏令时")
    func localClock() {
        #expect(ChatHeaderStatus.localTime(at: now, timeZoneIdentifier: melbourne) == "14:19")
        #expect(ChatHeaderStatus.localDate(at: now, timeZoneIdentifier: melbourne).contains("2026年9月17日"))
        let utc = ISO8601DateFormatter()
        let midnight = utc.date(from: "2026-10-30T15:30:00Z")!
        #expect(ChatHeaderStatus.localTime(at: midnight, timeZoneIdentifier: melbourne) == "02:30")
        #expect(ChatHeaderStatus.localDate(at: midnight, timeZoneIdentifier: melbourne).contains("2026年10月31日"))
        let winter = utc.date(from: "2026-01-15T12:00:00Z")!
        let summer = utc.date(from: "2026-07-15T12:00:00Z")!
        #expect(ChatHeaderStatus.localTime(at: winter, timeZoneIdentifier: "Europe/London") == "12:00")
        #expect(ChatHeaderStatus.localTime(at: summer, timeZoneIdentifier: "Europe/London") == "13:00")
    }
}

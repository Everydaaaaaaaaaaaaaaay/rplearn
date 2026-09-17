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
            regionName: "墨尔本",
            isStreaming: isStreaming
        )
    }

    @Test("任何状态都同时给出城市和当地时间", arguments: [
        NPCPresenceState.online,
        NPCPresenceState.recentlyActive,
        NPCPresenceState.offline,
    ])
    func everyStateKeepsRegionAndLocalTime(state: NPCPresenceState) {
        let value = text(state)
        #expect(value.contains("墨尔本"))
        #expect(value.contains("14:19"), "状态 \(state.rawValue) 缺少当地时间：\(value)")
    }

    @Test("刚刚在线使用较长的状态词，仍需保留城市与时间")
    func recentlyActiveKeepsFullDetail() {
        #expect(text(.recentlyActive) == "刚刚在线 · 墨尔本 14:19")
    }

    @Test("正在输入时仍显示城市与当地时间")
    func streamingKeepsFullDetail() {
        #expect(text(.online, isStreaming: true) == "正在输入 · 墨尔本 14:19")
    }

    @Test("离线状态带上最后在线时间，同时保留当前当地时间")
    func offlineKeepsLastActiveAndLocalTime() {
        #expect(
            text(.offline, lastActiveAt: now.addingTimeInterval(-2 * 60 * 60))
                == "12:19 在线过 · 墨尔本 14:19"
        )
        #expect(
            text(.offline, lastActiveAt: now.addingTimeInterval(-25 * 60 * 60))
                == "昨天 13:19 在线 · 墨尔本 14:19"
        )
        let older = now.addingTimeInterval(-5 * 24 * 60 * 60)
        #expect(text(.offline, lastActiveAt: older).hasPrefix("9月12日 14:19 在线 · 墨尔本 14:19"))
    }
}

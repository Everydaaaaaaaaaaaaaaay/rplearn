import DomainKit
import Foundation

/// 聊天页顶部状态文案。
///
/// 任何状态都必须同时给出「状态 · 城市 当地时间」，因为顶部只有这一行能说明
/// 对方在哪个城市、那边现在几点；文案变长时由 `ChatTitleView` 缩放显示，不再截断。
public enum ChatHeaderStatus {
    public static func text(
        presence: NPCPresenceSnapshot,
        at date: Date,
        regionName: String,
        isStreaming: Bool
    ) -> String {
        let timeZone = TimeZone(identifier: presence.timeZoneIdentifier)
        let clock = clockString(date, timeZone: timeZone)
        let city = "\(regionName) \(clock)"
        if isStreaming {
            return "正在输入 · \(city)"
        }
        switch presence.state {
        case .online:
            return "在线 · \(city)"
        case .recentlyActive:
            return "刚刚在线 · \(city)"
        case .offline:
            guard let lastActiveAt = presence.lastActiveAt else {
                return "离线 · \(city)"
            }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone ?? TimeZone(secondsFromGMT: 0)!
            let lastActive = clockString(lastActiveAt, timeZone: timeZone)
            if calendar.isDate(lastActiveAt, inSameDayAs: date) {
                return "\(lastActive) 在线过 · \(city)"
            }
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: date),
               calendar.isDate(lastActiveAt, inSameDayAs: yesterday) {
                return "昨天 \(lastActive) 在线 · \(city)"
            }
            let stamp = stampString(lastActiveAt, timeZone: timeZone)
            return "\(stamp) 在线 · \(city)"
        }
    }

    private static func clockString(_ date: Date, timeZone: TimeZone?) -> String {
        formatter(timeZone: timeZone, format: "HH:mm").string(from: date)
    }

    private static func stampString(_ date: Date, timeZone: TimeZone?) -> String {
        formatter(timeZone: timeZone, format: "M月d日 HH:mm").string(from: date)
    }

    private static func formatter(timeZone: TimeZone?, format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter
    }
}

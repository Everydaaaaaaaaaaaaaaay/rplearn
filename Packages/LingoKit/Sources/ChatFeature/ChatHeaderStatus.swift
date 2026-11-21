import DomainKit
import Foundation

/// 聊天顶部的在线状态与角色当地时间。
public enum ChatHeaderStatus {
    public static func text(
        presence: NPCPresenceSnapshot,
        at date: Date,
        isStreaming: Bool
    ) -> String {
        let timeZone = TimeZone(identifier: presence.timeZoneIdentifier)
        if isStreaming {
            return "正在输入"
        }
        switch presence.state {
        case .online:
            return "在线"
        case .recentlyActive:
            return "忙碌"
        case .offline:
            guard let lastActiveAt = presence.lastActiveAt else {
                return "离线"
            }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone ?? TimeZone(secondsFromGMT: 0)!
            let lastActive = clockString(lastActiveAt, timeZone: timeZone)
            if calendar.isDate(lastActiveAt, inSameDayAs: date) {
                return "\(lastActive)在线过"
            }
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: date),
               calendar.isDate(lastActiveAt, inSameDayAs: yesterday) {
                return "昨天\(lastActive)在线"
            }
            let stamp = stampString(lastActiveAt, timeZone: timeZone)
            return "\(stamp)在线"
        }
    }

    public static func localTime(at date: Date, timeZoneIdentifier: String) -> String {
        clockString(date, timeZone: TimeZone(identifier: timeZoneIdentifier))
    }

    public static func localDate(at date: Date, timeZoneIdentifier: String) -> String {
        formatter(timeZone: TimeZone(identifier: timeZoneIdentifier), format: "yyyy年M月d日 EEEE").string(from: date)
    }

    private static func clockString(_ date: Date, timeZone: TimeZone?) -> String {
        formatter(timeZone: timeZone, format: "HH:mm").string(from: date)
    }

    private static func stampString(_ date: Date, timeZone: TimeZone?) -> String {
        formatter(timeZone: timeZone, format: "M/d HH:mm").string(from: date)
    }

    private static func formatter(timeZone: TimeZone?, format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = timeZone ?? TimeZone(secondsFromGMT: 0)!
        formatter.dateFormat = format
        return formatter
    }
}

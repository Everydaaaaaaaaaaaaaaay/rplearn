import Foundation
import PersistenceKit

/// 角色世界中的可信时间锚点。只提供本地日期与时段，不伪造天气、营业状态或外部事件。
enum RoleplayTemporalContext {
    private static let timeZoneIdentifiers: [String: String] = [
        "london": "Europe/London",
        "melbourne": "Australia/Melbourne",
        "newyork": "America/New_York",
        "capetown": "Africa/Johannesburg",
        "singapore": "Asia/Singapore",
        "dublin": "Europe/Dublin",
        "edinburgh": "Europe/London",
        "vancouver": "America/Vancouver",
        "auckland": "Pacific/Auckland",
        "nairobi": "Africa/Nairobi",
        "toronto": "America/Toronto",
        "sydney": "Australia/Sydney",
        "neworleans": "America/Chicago",
        "manchester": "Europe/London",
        "kingston": "America/Jamaica",
    ]

    static func timeZone(for regionID: String) -> TimeZone {
        let identifier = timeZoneIdentifiers[regionID.lowercased()] ?? "Etc/UTC"
        return TimeZone(identifier: identifier) ?? TimeZone(secondsFromGMT: 0)!
    }

    static func calendar(for regionID: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone(for: regionID)
        return calendar
    }

    static func currentSituation(regionID: String, at date: Date,
                                 profile: NPCActivityProfile? = nil,
                                 userTimeZone: TimeZone = .autoupdatingCurrent) -> String {
        var calendar = calendar(for: regionID)
        if let identifier = profile?.timeZoneIdentifier,
           let zone = TimeZone(identifier: identifier) { calendar.timeZone = zone }
        let hour = calendar.component(.hour, from: date)
        return """
        ## 可信的当前时间语境
        在 \(regionID)，现在是 \(displayDate(date, timeZone: calendar.timeZone))，属于\(dayPeriod(hour))。
        用户设备时间是 \(displayDate(date, timeZone: userTimeZone))；这不能证明其实际所在位置。
        区分你的当地时间和用户的时间。询问用户的早晨、用餐或一天情况时，以用户设备时间为准。
        正午就是中午，不代表下午已经过去。不要回顾性询问用户尚未经历的时段。
        你通常的当地作息类型是 \(profile?.rhythm.rawValue ?? "daytime")。睡眠、工作、用餐和休闲应符合该作息和职业。
        在通常睡觉时段回复只是短暂例外，不代表你经常整夜工作或社交。
        作息只是倾向，不能证明具体班次或员工餐。保留既有计划，不编造精确日程。
        把这段作为私有世界语境，不要照着复述。让它默默约束问候、睡眠、用餐、工作和有时效的计划。
        除非提供的对话或记忆中有证据，不得声称知道实时天气、营业时间、新闻或其他外部事实。只有自然需要时才提及日期或时间。
        """
    }

    static func transcriptTimestamp(
        _ date: Date,
        regionID: String?
    ) -> String {
        let timeZone = regionID.map(timeZone(for:)) ?? TimeZone(secondsFromGMT: 0)!
        return displayDate(date, timeZone: timeZone)
    }

    private static func displayDate(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEEE, yyyy-MM-dd HH:mm zzz"
        return formatter.string(from: date)
    }

    private static func dayPeriod(_ hour: Int) -> String {
        switch hour {
        case 0..<5: "深夜"
        case 5..<9: "清晨"
        case 9..<12: "上午"
        case 12..<14: "正午"
        case 14..<17: "下午"
        case 17..<21: "傍晚"
        default: "夜间"
        }
    }
}

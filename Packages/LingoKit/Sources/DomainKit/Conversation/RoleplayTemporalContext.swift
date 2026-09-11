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
        ## Trusted present-time context
        In \(regionID), it is \(displayDate(date, timeZone: calendar.timeZone)), during the \(dayPeriod(hour)).
        The user's device clock is \(displayDate(date, timeZone: userTimeZone)); it does not establish their physical location.
        Keep your local time and the user's time distinct. Use the user's clock for questions about their morning, meals or day.
        Noon is midday, not an afternoon already spent. Never ask retrospectively about a period that has not elapsed for the user.
        Your usual local activity rhythm is \(profile?.rhythm.rawValue ?? "daytime"). Let sleep, work, meals and leisure follow this rhythm and your occupation.
        A reply during usual sleeping hours is a brief exception, not proof you routinely work or socialize all night.
        A routine is a tendency, not evidence of a specific shift or staff meal. Preserve established plans and do not invent exact schedules.
        Treat this as private world context, not a sentence you must repeat. Let it quietly constrain greetings, sleep, \
        meals, work and time-sensitive plans. Do not claim live weather, opening hours, news or another external fact \
        unless it appears in supplied conversation or memory. Mention the date or clock only when it matters naturally.
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
        case 0..<5: "late night"
        case 5..<9: "early morning"
        case 9..<12: "morning"
        case 12..<14: "midday"
        case 14..<17: "afternoon"
        case 17..<21: "evening"
        default: "night"
        }
    }
}

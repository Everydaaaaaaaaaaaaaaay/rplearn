import Foundation

public enum AppointmentDisplayTime {
    public static func date(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    public static func userZone(_ identifier: String?) -> TimeZone {
        identifier.flatMap(TimeZone.init(identifier:)) ?? .autoupdatingCurrent
    }

    public static func zoneLabel(_ zone: TimeZone) -> String {
        if ["Asia/Shanghai", "Asia/Chongqing", "Asia/Chungking", "Asia/Harbin", "PRC"].contains(zone.identifier) {
            return "北京时间"
        }
        return zone.localizedName(for: .generic, locale: Locale(identifier: "zh_CN")) ?? zone.identifier
    }

    public static func scheduled(_ value: String, zone: TimeZone) -> String {
        guard let instant = date(value) else { return value }
        return formatted(instant, zone: zone, format: "M月d日 EEE · HH:mm")
    }

    public static func timeline(_ value: String, zone: TimeZone) -> String? {
        guard let instant = date(value) else { return nil }
        return formatted(instant, zone: zone, format: "M月d日 EEE HH:mm", locale: "zh_CN")
    }

    public static func window(opens: String, closes: String, zone: TimeZone) -> String {
        guard let start = date(opens), let end = date(closes) else { return "\(opens)–\(closes)" }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let endFormat = calendar.isDate(start, inSameDayAs: end) ? "HH:mm" : "M月d日 HH:mm"
        return "\(scheduled(opens, zone: zone))–\(formatted(end, zone: zone, format: endFormat))"
    }

    /// 界面是中文，约定时间也用中文日期（与 `timeline` 一致）。
    private static func formatted(_ date: Date, zone: TimeZone, format: String, locale: String = "zh_CN") -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: locale)
        formatter.timeZone = zone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}

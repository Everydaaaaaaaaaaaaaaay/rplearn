import Foundation

public enum AppointmentDisplayTime {
    private static let beijingZone = TimeZone(identifier: "Asia/Shanghai")!

    public static func date(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    public static func beijing(_ value: String) -> String {
        guard let instant = date(value) else { return value }
        return formatted(instant, zone: beijingZone, format: "EEE, d MMM yyyy · HH:mm")
    }

    public static func local(_ value: String, city: String, timeZone: String) -> String {
        guard let instant = date(value), let zone = TimeZone(identifier: timeZone) else { return city }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = beijingZone
        let beijingDay = calendar.dateComponents([.era, .year, .month, .day], from: instant)
        calendar.timeZone = zone
        let localDay = calendar.dateComponents([.era, .year, .month, .day], from: instant)
        let format = localDay == beijingDay ? "H:mm" : "d MMM yyyy H:mm"
        return "\(city) \(formatted(instant, zone: zone, format: format))"
    }

    public static func beijingWindow(opens: String, closes: String) -> String {
        guard let start = date(opens), let end = date(closes) else { return "\(opens)–\(closes)" }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = beijingZone
        let endFormat = calendar.isDate(start, inSameDayAs: end) ? "HH:mm" : "d MMM yyyy HH:mm"
        return "\(beijing(opens))–\(formatted(end, zone: beijingZone, format: endFormat))"
    }

    private static func formatted(_ date: Date, zone: TimeZone, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = zone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}

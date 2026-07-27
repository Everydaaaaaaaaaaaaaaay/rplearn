import Foundation

/// 主动消息的节奏规则：保持轻量随机，并把通知收敛到白天。
public enum ProactiveMessageSchedulePolicy {
    public static let maximumPendingCount = 2

    /// 根据注入的随机值计算下一次时间，便于稳定测试。
    ///
    /// - Parameters:
    ///   - randomUnit: 取值会被限制在 0...1。
    ///   - minimumHours: 最短安静时间。
    ///   - maximumHours: 最长安静时间。
    public static func nextDate(
        after anchor: Date,
        randomUnit: Double,
        minimumHours: Double,
        maximumHours: Double,
        calendar: Calendar = .current
    ) -> Date {
        let unit = min(max(randomUnit, 0), 1)
        let hours = minimumHours + (maximumHours - minimumHours) * unit
        let proposed = anchor.addingTimeInterval(hours * 60 * 60)
        let hour = calendar.component(.hour, from: proposed)

        if hour < 10 {
            return calendar.date(bySettingHour: 10, minute: calendar.component(.minute, from: proposed), second: 0, of: proposed)
                ?? proposed
        }
        if hour >= 21 {
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: proposed) ?? proposed
            return calendar.date(bySettingHour: 10, minute: calendar.component(.minute, from: proposed), second: 0, of: tomorrow)
                ?? tomorrow
        }
        return proposed
    }
}

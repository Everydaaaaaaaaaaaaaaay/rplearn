import Foundation
import PersistenceKit

public extension Notification.Name {
    /// 聊天时间线改变后让 App 重新核对尚未发送的主动消息，避免旧文案穿越到新语境。
    static let roleplayConversationDidChange = Notification.Name(
        "LingoTripRoleplayConversationDidChange"
    )
}

/// 主动消息的节奏规则：保持轻量随机，并把通知收敛到白天。
public enum ProactiveMessageSchedulePolicy {
    public static let maximumPendingCount = 2
    public static let minimumDeliveryQuietHours: Double = 30

    /// 同一位角色在用户尚未回应时最多自然跟进一次，不能每隔几天连续追问。
    public static func shouldScheduleCheckIn(
        recentMessages: [MessageDTO],
        hasPendingCheckIn: Bool
    ) -> Bool {
        guard !hasPendingCheckIn else { return false }
        let messages = relevantMessages(recentMessages)
        guard let latest = messages.last,
              latest.role == .assistant,
              !latest.isInterrupted
        else { return false }
        return unansweredAssistantBurstCount(messages) <= 1
    }

    /// 到期写入前重新核对时间线；期间只要发生新对话，旧文案就作废。
    public static func shouldDeliverCheckIn(
        recentMessages: [MessageDTO],
        scheduledAfterMessageID: UUID?,
        at date: Date
    ) -> Bool {
        let messages = relevantMessages(recentMessages)
        guard let latest = messages.last,
              latest.id == scheduledAfterMessageID,
              latest.role == .assistant,
              !latest.isInterrupted,
              date.timeIntervalSince(latest.createdAt) >= minimumDeliveryQuietHours * 60 * 60
        else { return false }
        return unansweredAssistantBurstCount(messages) <= 1
    }

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

    private static func relevantMessages(_ messages: [MessageDTO]) -> [MessageDTO] {
        messages
            .filter { $0.role != .coach && !$0.text.isEmpty }
            .sorted {
                if $0.createdAt == $1.createdAt { return $0.orderIndex < $1.orderIndex }
                return $0.createdAt < $1.createdAt
            }
    }

    /// 连续气泡属于同一回合；只有相隔明显时长的角色消息才算一次新的未回应跟进。
    private static func unansweredAssistantBurstCount(_ messages: [MessageDTO]) -> Int {
        let lastUserIndex = messages.lastIndex { $0.role == .user }
        let unanswered = messages[(lastUserIndex.map { messages.index(after: $0) } ?? messages.startIndex)...]
            .filter { $0.role == .assistant }
        guard !unanswered.isEmpty else { return 0 }

        var bursts = 1
        for pair in zip(unanswered, unanswered.dropFirst())
        where pair.1.createdAt.timeIntervalSince(pair.0.createdAt) >= 30 * 60 {
            bursts += 1
        }
        return bursts
    }
}

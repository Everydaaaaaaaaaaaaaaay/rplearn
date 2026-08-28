import DesignSystem
import Foundation
import PersistenceKit

/// 即时通讯时间轴的确定性展示规则。
///
/// 时间提示不逐条重复，只在会话起点、跨自然日或明显停顿后出现；同一发送者在
/// 短时间内的连续消息则组成一个视觉消息组。
enum ChatTimelinePolicy {
    static let groupingInterval: TimeInterval = 5 * 60
    static let timeMarkerInterval: TimeInterval = 15 * 60

    enum DeliveryReceipt: Equatable {
        case delivered
        case read

        var label: String {
            switch self {
            case .delivered: "已送达"
            case .read: "已读"
            }
        }

        var systemImage: String {
            switch self {
            case .delivered: "checkmark"
            case .read: "checkmark.circle.fill"
            }
        }
    }

    static func shouldShowTimeMarker(
        in messages: [MessageDTO],
        at index: Int,
        calendar: Calendar = .current
    ) -> Bool {
        guard messages.indices.contains(index) else { return false }
        guard index > 0 else { return true }

        let previous = messages[index - 1]
        let current = messages[index]
        guard calendar.isDate(previous.createdAt, inSameDayAs: current.createdAt) else {
            return true
        }
        return current.createdAt.timeIntervalSince(previous.createdAt) >= timeMarkerInterval
    }

    static func groupPosition(
        in messages: [MessageDTO],
        at index: Int
    ) -> MessageBubbleGroupPosition {
        guard messages.indices.contains(index) else { return .single }
        let joinsPrevious = index > 0 && canGroup(messages[index - 1], messages[index])
        let joinsNext = index < messages.count - 1 && canGroup(messages[index], messages[index + 1])

        return switch (joinsPrevious, joinsNext) {
        case (false, false): .single
        case (false, true): .first
        case (true, true): .middle
        case (true, false): .last
        }
    }

    static func canGroup(_ earlier: MessageDTO, _ later: MessageDTO) -> Bool {
        guard earlier.role == later.role,
              earlier.role != .coach,
              earlier.kind != .storyLine,
              later.kind != .storyLine,
              Calendar.current.isDate(earlier.createdAt, inSameDayAs: later.createdAt)
        else { return false }

        let interval = later.createdAt.timeIntervalSince(earlier.createdAt)
        return interval >= 0 && interval < groupingInterval
    }

    static func showsIncomingAvatar(
        in messages: [MessageDTO],
        at index: Int,
        hasTypingContinuation: Bool
    ) -> Bool {
        guard messages.indices.contains(index), messages[index].role == .assistant else {
            return false
        }
        if hasTypingContinuation, index == messages.indices.last { return false }
        let position = groupPosition(in: messages, at: index)
        return position == .single || position == .last
    }

    static func showsOutgoingAvatar(in messages: [MessageDTO], at index: Int) -> Bool {
        guard messages.indices.contains(index), messages[index].role == .user else {
            return false
        }
        let position = groupPosition(in: messages, at: index)
        return position == .single || position == .last
    }

    static func deliveryReceipt(
        in messages: [MessageDTO],
        at index: Int,
        isReplying: Bool
    ) -> DeliveryReceipt? {
        guard messages.indices.contains(index), messages[index].role == .user else { return nil }
        guard messages.lastIndex(where: { $0.role == .user }) == index else { return nil }

        let hasLaterReply = messages[(index + 1)...].contains { $0.role == .assistant }
        return hasLaterReply || isReplying ? .read : .delivered
    }

    static func timeMarkerText(
        for date: Date,
        relativeTo now: Date = .now,
        calendar: Calendar = .current,
        locale: Locale = Locale(identifier: "zh_CN")
    ) -> String {
        let time = formatter(
            template: "HHmm",
            calendar: calendar,
            locale: locale
        ).string(from: date)

        if calendar.isDate(date, inSameDayAs: now) {
            return "今天 \(time)"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "昨天 \(time)"
        }

        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let dayTemplate = sameYear ? "MMMdEEEE" : "yyyyMMMdEEEE"
        let day = formatter(
            template: dayTemplate,
            calendar: calendar,
            locale: locale
        ).string(from: date)
        return "\(day) \(time)"
    }

    static func exactTimeText(
        for date: Date,
        calendar: Calendar = .current,
        locale: Locale = Locale(identifier: "zh_CN")
    ) -> String {
        formatter(
            template: "yyyyMMMdEEEEHHmm",
            calendar: calendar,
            locale: locale
        ).string(from: date)
    }

    private static func formatter(
        template: String,
        calendar: Calendar,
        locale: Locale
    ) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }
}

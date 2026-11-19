import BackendKit
import DesignSystem
import DomainKit
import Foundation
import PersistenceKit
import SwiftUI
import UIKit

struct ChatTimelineEvent: View {
    enum Kind: Equatable {
        case memory, affinity, mood, appointment

        var icon: String {
            switch self {
            case .memory: "bookmark.fill"
            case .affinity: "heart.fill"
            case .mood: "cloud.fill"
            case .appointment: "calendar.badge.checkmark"
            }
        }

        var tint: Color {
            switch self {
            case .memory:
                Color(light: UIColor(red: 0.39, green: 0.28, blue: 0.59, alpha: 1),
                      dark: UIColor(red: 0.79, green: 0.70, blue: 0.97, alpha: 1))
            case .affinity:
                Color(light: UIColor(red: 0.61, green: 0.24, blue: 0.36, alpha: 1),
                      dark: UIColor(red: 0.99, green: 0.65, blue: 0.76, alpha: 1))
            case .mood:
                Color(light: UIColor(red: 0.29, green: 0.40, blue: 0.56, alpha: 1),
                      dark: UIColor(red: 0.67, green: 0.79, blue: 0.95, alpha: 1))
            case .appointment:
                Color(light: UIColor(red: 0.16, green: 0.43, blue: 0.34, alpha: 1),
                      dark: UIColor(red: 0.59, green: 0.87, blue: 0.74, alpha: 1))
            }
        }
    }

    let kind: Kind
    let title: String
    var action: (() -> Void)? = nil

    var body: some View {
        Group {
            if let action {
                Button(action: action) { capsule }
                    .buttonStyle(.plain)
                    .accessibilityHint("查看约定详情")
            } else {
                capsule
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("chat.timeline.event")
    }

    private var capsule: some View {
        HStack(spacing: 6) {
            Image(systemName: kind.icon)
                .accessibilityHidden(true)
            Text(title)
                .fixedSize(horizontal: false, vertical: true)
            if action != nil {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .accessibilityHidden(true)
            }
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(kind.tint)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(kind.tint.opacity(kind == .appointment ? 0.13 : 0.095), in: Capsule())
        .overlay { Capsule().strokeBorder(kind.tint.opacity(0.15), lineWidth: 1) }
    }
}

extension ChatTimelineEvent {
    init?(_ event: ChatMessageTimelineEvent, name: String) {
        switch event.kind {
        case .memory:
            let text: String
            switch event.state {
            case "remembered": text = "记住了你的话"
            case "refined": text = "记下了更多细节"
            case "corrected": text = "更正了之前的记忆"
            case "updated": text = "更新了对这件事的记忆"
            case "recalled": text = "提起了以前记下的事"
            default: return nil
            }
            self.init(kind: .memory, title: "\(name) \(text)")
        case .relationship:
            let text: String
            switch event.state {
            case "repair": text = "你和\(name)之间的紧张缓和了一些"
            case "strained": text = "你和\(name)之间有了些紧张"
            case "trustIncreased": text = "\(name) 对你多了几分信任"
            case "trustDecreased": text = "\(name) 对你的信任有所下降"
            case "closer": text = "你和\(name)相处得更自在了"
            case "distant": text = "你和\(name)之间多了些距离"
            case "affinity":
                guard let delta = event.delta, delta.isFinite, abs(delta) >= 0.15 else { return nil }
                let value = abs(delta).formatted(.number.precision(.fractionLength(1)))
                text = "\(name) 的好感度 \(delta > 0 ? "+" : "−")\(value)"
            default: return nil
            }
            self.init(kind: .affinity, title: text)
        case .mood:
            guard let mood = ChatCharacterMood(rawValue: event.state) else { return nil }
            let phrase: String
            if let secondary = event.secondary.flatMap(ChatCharacterMood.init(rawValue:)) {
                phrase = "既\(mood.chinesePhrase)，又\(secondary.chinesePhrase)"
            } else {
                phrase = mood.chinesePhrase
            }
            self.init(kind: .mood, title: "\(name) 看起来\(phrase)")
        }
    }

    init?(_ event: BackendAppointmentTimelineEvent, name: String, action: (() -> Void)?) {
        let time: String
        if let date = AppointmentDisplayTime.date(event.startsAt), let zone = TimeZone(identifier: event.timeZone) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.timeZone = zone
            formatter.dateFormat = "M月d日 EEE HH:mm"
            time = formatter.string(from: date)
        } else {
            time = ""
        }
        let text: String
        switch event.kind {
        case "confirmed": text = "和 \(name) 约好了\(time.isEmpty ? "" : " · " + time)"
        case "rescheduled": text = time.isEmpty ? "约定时间已调整" : "约定改到了 \(time)"
        case "relocated": text = "约定地点改到了\(event.placeName)"
        case "rescheduledAndRelocated": text = "约定改到了 \(time) · \(event.placeName)"
        case "cancelled": text = "这次约定已取消"
        case "expired": text = "这次约定已过赴约时限"
        case "started": text = "和 \(name) 的赴约开始了"
        case "completed": text = "和 \(name) 的赴约已完成"
        default: return nil
        }
        self.init(kind: .appointment, title: text, action: action)
    }
}

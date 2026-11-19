#if DEBUG
import PersistenceKit

public enum ChatTimelineEventPreview {
    public static let lines: [(MessageRole, String)] = [
        (.user, "I come down here whenever I need some quiet."),
        (.assistant, "I’ll remember that. It’s a good spot."),
        (.assistant, "I’m a little off today. It’s been a rough morning."),
        (.user, "Want some quiet company? We don’t have to talk."),
        (.assistant, "Actually, yeah. I’d like that."),
        (.user, "Saturday at three, by the river?"),
        (.assistant, "Saturday at three. See you by the steps."),
        (.user, "Deal. I’ll bring the good biscuits."),
        (.assistant, "Okay, now I’m definitely coming.")
    ]

    static func event(after message: MessageDTO) -> ChatTimelineEvent? {
        switch message.orderIndex {
        case 1: ChatTimelineEvent(kind: .memory, title: "Ruby 记住了你的话")
        case 2: ChatTimelineEvent(kind: .mood, title: "Ruby 看起来有点低落")
        case 4: ChatTimelineEvent(kind: .affinity, title: "Ruby 的好感度 +0.2")
        case 6: ChatTimelineEvent(kind: .appointment, title: "和 Ruby 约好了 · 周六 15:00")
        default: nil
        }
    }
}
#endif

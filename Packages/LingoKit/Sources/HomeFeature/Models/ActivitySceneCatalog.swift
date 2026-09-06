import Foundation

public enum ActivitySceneID: String, CaseIterable, Identifiable, Sendable {
    case cafe
    public var id: String { rawValue }
    public var title: String { "街角咖啡馆" }
    var subtitle: String { "借一个座位，让一句问候有机会发生。" }
    var actions: [SceneActivity] { SceneActivity.catalog }
    var poster: String { "activity-cafe-interior" }
}

/// Authored social intentions, not a fixed personality or an anonymous quiz.
public struct SceneActivity: Identifiable, Equatable, Sendable {
    public let id: String
    public let scene: ActivitySceneID
    let title: String
    let symbol: String
    let introduction: String
    let steps: [Step]
    let closing: String

    struct Step: Equatable, Sendable {
        let context: String
        let question: String
        let choices: [Choice]
    }
    struct Choice: Equatable, Sendable {
        let english: String
        let chinese: String
        let response: String
    }

    var anchor: ActivitySceneAnchor {
        switch id {
        case "cafe-seat": .cafeCup
        case "cafe-neighbourhood": .cafeMenu
        default: .cafeBook
        }
    }

    // Share one stable library pool, never run IDs or generated free text.
    static let encounterPoolID = "social-cafe-v1"
    private static let farewell = Step(
        context: "短短的交流之后，你可以试着留下联系，也可以让这次问候停在这里。",
        question: "接下来，你想怎样回应？",
        choices: [
            .init(english: "Would you like to keep in touch?", chinese: "你愿意以后保持联系吗？",
                  response: "keep in touch 是保持联系。邀请给对方选择空间，不代表对方一定会答应。"),
            .init(english: "It was nice talking to you. Enjoy your day!", chinese: "很高兴和你聊了聊，祝你今天愉快！",
                  response: "nice talking to you 是自然的告别，不需要勉强继续话题。")])

    static let catalog: [Self] = [
        .init(id: "cafe-seat", scene: .cafe, title: "共用一桌", symbol: "cup.and.saucer",
              introduction: "共用桌旁留着一把空椅子。先问一句，再看看对方是否有聊天的兴致。",
              steps: [
                .init(context: "一位客人把随身物品收到桌边。你想先确认旁边的空位。",
                      question: "怎样自然地开口？", choices: [
                        .init(english: "Excuse me, is this seat taken?", chinese: "打扰一下，这个座位有人吗？",
                              response: "taken 在这里表示座位已被占用，先确认而不是直接坐下。"),
                        .init(english: "Would you mind if I sat here?", chinese: "你介意我坐在这里吗？",
                              response: "Would you mind… 是委婉请求；Not at all 表示完全不介意。")]), farewell],
              closing: "一张共用桌，可以容纳不同的生活节奏。"),
        .init(id: "cafe-neighbourhood", scene: .cafe, title: "聊聊附近", symbol: "map",
              introduction: "在菜单旁想一想接下来去哪里。你向同桌的人问起附近，也许对方同样刚刚来到这里。",
              steps: [
                .init(context: "饮品还没喝完，你和旁边的客人都暂时停下了脚步。你打算问问周边。",
                      question: "你想从什么话题开始？", choices: [
                        .init(english: "Have you found any nice places nearby?", chinese: "你在附近发现什么不错的地方了吗？",
                              response: "found 邀请对方分享亲身发现，不默认对方一定是本地人。"),
                        .init(english: "Are you exploring this area too?", chinese: "你也在探索这一带吗？",
                              response: "too 把话题放在双方的共同处境上，不把陌生人当成导游。")]), farewell],
              closing: "交换一点见闻，比收集一份标准答案更有意思。"),
        .init(id: "cafe-book", scene: .cafe, title: "借书开场", symbol: "book",
              introduction: "店里有几本供客人翻阅的书。你拿起一本，旁边的人也看了一眼——不必都是书迷才能聊两句。",
              steps: [
                .init(context: "你把共享书放到桌上，旁边的客人注意到了封面。你想试着聊一聊。",
                      question: "怎样给对方一个轻松的话题？", choices: [
                        .init(english: "Does this cover remind you of anything?", chinese: "这个封面让你想起了什么吗？",
                              response: "remind you of 邀请对方说联想，不要求对方读过这本书。"),
                        .init(english: "Do you ever pick a book just for its cover?", chinese: "你会仅仅因为封面就挑一本书吗？",
                              response: "ever 问的是有没有过这样的经历，不预设对方的阅读习惯。")]), farewell],
              closing: "一段话题的起点，不必是一模一样的爱好。")
    ]
}

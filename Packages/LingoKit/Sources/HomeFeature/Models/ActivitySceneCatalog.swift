import Foundation

public enum ActivitySceneID: String, CaseIterable, Identifiable, Sendable {
    case cafe, bookstall, flowerstall
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .cafe: "街角咖啡馆"
        case .bookstall: "街边旧书摊"
        case .flowerstall: "街角花摊"
        }
    }
    var actions: [SceneActivity] { SceneActivity.catalog.filter { $0.scene == self } }
    var poster: String { "activity-\(rawValue)-ambient-v4" }
    var encounterContext: String {
        switch self {
        case .cafe:
            "An ordinary shared-table outdoor cafe on a pedestrian courtyard. A pause between everyday errands; no assumption of occupation, coffee or book interests."
        case .bookstall:
            "An ordinary outdoor second-hand book stall on a pedestrian street. People may be buying a gift, waiting, browsing or passing. Do not assume literary interests or that they are staff."
        case .flowerstall:
            "An ordinary street flower stall. People may be running errands, buying flowers for themselves or others, accompanying someone or just stopping. Do not assume gardening knowledge, gender, a romantic occasion or that they are staff."
        }
    }
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
        case "cafe-neighbourhood": .cafeSill
        case "cafe-taste": .cafePastry
        case "bookstall-cover": .bookstallBook
        case "bookstall-recommend": .bookstallRecommendations
        case "bookstall-travel": .bookstallOpenBook
        case "flowerstall-colour": .flowerstallBucket
        case "flowerstall-bouquet": .flowerstallBouquet
        case "flowerstall-queue": .flowerstallTable
        default: .cafePastry
        }
    }

    // Historical ID intentionally retained across ALL scenes to preserve the
    // existing public pool. A place is an encounter context, not a demographic silo.
    static let encounterPoolID = "social-cafe-v1"
    static let farewell = Step(
        context: "短短的交流之后，你可以试着留下联系，也可以让这次问候停在这里。",
        question: "接下来，你想怎样回应？",
        choices: [
            .init(english: "Would you like to keep in touch?", chinese: "你愿意以后保持联系吗？",
                  response: "keep in touch 是保持联系。邀请给对方选择空间，不代表对方一定会答应。"),
            .init(english: "It was nice talking to you. Enjoy your day!", chinese: "很高兴和你聊了聊，祝你今天愉快！",
                  response: "nice talking to you 是自然的告别，不需要勉强继续话题。")])

    static let catalog: [Self] = cafeCatalog + bookstallCatalog + flowerstallCatalog
    private static let cafeCatalog: [Self] = [
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
              introduction: "看看桌边的街景，想一想接下来去哪里。你向同桌的人问起附近，也许对方同样刚刚来到这里。",
              steps: [
                .init(context: "饮品还没喝完，你和旁边的客人都暂时停下了脚步。你打算问问周边。",
                      question: "你想从什么话题开始？", choices: [
                        .init(english: "Have you found any nice places nearby?", chinese: "你在附近发现什么不错的地方了吗？",
                              response: "found 邀请对方分享亲身发现，不默认对方一定是本地人。"),
                        .init(english: "Are you exploring this area too?", chinese: "你也在探索这一带吗？",
                              response: "too 把话题放在双方的共同处境上，不把陌生人当成导游。")]), farewell],
              closing: "交换一点见闻，比收集一份标准答案更有意思。"),
        .init(id: "cafe-taste", scene: .cafe, title: "聊聊口味", symbol: "fork.knife",
              introduction: "咖啡和点心端上来了。你和同桌的人对上目光，可以聊聊各自喜欢的口味，不必懂咖啡。",
              steps: [
                .init(context: "你放下杯子，旁边的客人刚好也抬起头。你想从轻松的饮食偏好聊起，不打断对方用餐。",
                      question: "怎样给对方一个轻松的话题？", choices: [
                        .init(english: "Do you usually go for something sweet or savoury?", chinese: "你通常会选甜口的还是咸口的？",
                              response: "go for 表示选择；savoury 指咸香口味，对方也可以说两种都喜欢。"),
                        .init(english: "Do you have a favourite drink for a day like this?", chinese: "像今天这样的日子，你有没有特别想喝的饮品？",
                              response: "a day like this 邀请分享当下偏好，不预设对方一定喝咖啡。")]), farewell],
              closing: "一段话题的起点，不必是一模一样的爱好。")
    ]
}

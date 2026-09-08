import Foundation

public enum ActivitySceneID: String, CaseIterable, Identifiable, Sendable {
    case park, pond, raincafe

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .park: "公园小憩"
        case .pond: "池畔观察"
        case .raincafe: "雨天咖啡馆"
        }
    }

    var actions: [SceneActivity] { SceneActivity.catalog.filter { $0.scene == self } }

    var encounterContext: String {
        switch self {
        case .park:
            "A quiet shared table beside a city park. A map, coffee and notebook are ordinary reasons to pause; do not assume the other visitor is local or shares a particular hobby."
        case .pond:
            "A waterside observation ledge with binoculars, a sketchbook and postcards. Visitors may be resting or looking at the water; do not assume artistic expertise or personal circumstances."
        case .raincafe:
            "A cafe table beside a rain-covered window. Pastries and napkins are within reach while rain shifts across the glass; do not assume occupation, relationship, dietary preference or familiarity with the city."
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
        case "park-route": .map
        case "park-seat": .cup
        case "park-notes": .journal
        case "pond-reflection": .binoculars
        case "pond-sketch": .sketchbook
        case "pond-postcard": .postcard
        case "rain-weather": .rainWindow
        case "rain-pastry": .rainPastry
        case "rain-napkin": .rainNapkins
        default: .map
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
                  response: "nice talking to you 是自然的告别，不需要勉强继续话题。")
        ])

    static let catalog: [Self] = parkCatalog + pondCatalog + rainCafeCatalog

    private static let parkCatalog: [Self] = [
        .init(id: "park-route", scene: .park, title: "问问路线", symbol: "map",
              introduction: "桌上的地图摊开着。你和旁边停下来的人都在辨认方向，可以从一条散步路线自然地聊起。",
              steps: [
                .init(context: "你指了指地图上的水边小路，对方也凑近看了一眼。你不确定对方是不是本地人。",
                      question: "怎样开口比较自然？", choices: [
                        .init(english: "Are you looking for a walking route too?", chinese: "你也在找散步路线吗？",
                              response: "too 从共同处境开始，不把陌生人直接当成当地向导。"),
                        .init(english: "Does this path look like a good way to the bridge?", chinese: "这条路看起来适合走到桥边吗？",
                              response: "look like 给判断留有余地，对方即使不熟悉这里也容易回应。")]),
                farewell],
              closing: "从同一张地图出发，也可以交换两种走法。"),
        .init(id: "park-seat", scene: .park, title: "喝口咖啡", symbol: "cup.and.saucer",
              introduction: "杯里的咖啡还热着。先喝一口，再看看远处的桥和草地。",
              steps: [
                .init(context: "你端起咖啡喝了一口。附近也有人停下来看向远处的桥，你们恰好在看同一处风景。",
                      question: "怎样从眼前的景色自然开口？", choices: [
                        .init(english: "The view is lovely from here, isn't it?", chinese: "从这里看风景很不错，对吧？",
                              response: "from here 把话题放在共同看见的景色上，不涉及彼此的座位或桌面。"),
                        .init(english: "It's a peaceful spot for a short break.", chinese: "这里很适合短暂休息一下。",
                              response: "a short break 表达当下的小憩，也给对方留下简单回应或继续赶路的空间。")]),
                farewell],
              closing: "一口咖啡之后，也可以从共同看见的风景开始一句简单交流。"),
        .init(id: "park-notes", scene: .park, title: "交换见闻", symbol: "book.closed",
              introduction: "笔记本里刚记下一点沿途见闻。另一位访客也在看远处的桥，你可以分享一个细节，不必追问行程。",
              steps: [
                .init(context: "桥上的车流隐约可见，跑者已经从草坪边经过。你们都暂时没有赶路。",
                      question: "你想怎样分享眼前的一刻？", choices: [
                        .init(english: "I like how calm it feels here, even with the traffic nearby.", chinese: "虽然附近有车流，我还是很喜欢这里的平静。",
                              response: "even with 表达两种同时存在的感受，不要求对方赞同。"),
                        .init(english: "What would you remember about this place?", chinese: "你会记住这里的什么？",
                              response: "what would you remember 是开放邀请，不预设对方的旅行目的。")]),
                farewell],
              closing: "一段见闻不必很长，足够让两个人看见彼此注意到的不同。")
    ]
}

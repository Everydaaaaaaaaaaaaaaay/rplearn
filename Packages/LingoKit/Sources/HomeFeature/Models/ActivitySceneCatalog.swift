import Foundation

/// Authored, offline activities. These are learning scenes, not claims of live
/// location, real purchases or conversations with a newly created contact.
public enum ActivitySceneID: String, CaseIterable, Identifiable, Sendable {
    case park, pond
    public var id: String { rawValue }
    public var title: String { self == .park ? "公园小憩" : "池畔观察" }
    var subtitle: String { self == .park ? "一张地图，一杯咖啡，一点闲暇。" : "把匆忙留在身后，看水面慢慢变换。" }
    var actions: [SceneActivity] { SceneActivity.catalog.filter { $0.scene == self } }
    var poster: String { "activity-\(rawValue)-poster" }
    var table: String { self == .park ? "activity-table" : "activity-pond-table" }
    var tableTop: CGFloat { self == .park ? 1058 : 848 }
    var videoHeight: CGFloat { self == .park ? 1108 : 852 }
}

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
        case "walk": .map
        case "coffee": .cup
        case "journal": .journal
        case "observe": .binoculars
        case "sketch": .sketchbook
        default: .postcard
        }
    }

    static let catalog: [Self] = [
        .init(id: "walk", scene: .park, title: "读图出发", symbol: "map",
              introduction: "空出半小时，选一条适合自己的散步路线。在这段问路情境中，先说清自己的偏好，再确认听到的方向。",
              steps: [
                .init(context: "地图上有一条绕水边的路，也有一条穿过树荫的路。", question: "你想怎样开始问路？", choices: [
                    .init(english: "Is there a path by the water?", chinese: "有沿着水边的小路吗？", response: "你明确说出了想去的地方。by the water 指水边，并不是走进水里。"),
                    .init(english: "Which path has more shade?", chinese: "哪条路树荫更多？", response: "你先表达了舒适度偏好。shade 是树荫；用 which 比较眼前的几条路很自然。")]),
                .init(context: "练习中的指路人回答：两条路都会回到这里。水边约二十分钟，树荫下约十分钟。", question: "怎样确认自己理解了方向？", choices: [
                    .init(english: "So I follow this path to the water?", chinese: "所以我沿这条路走到水边，对吗？", response: "你用自己的话复述方向，给对方一个纠正误解的机会。"),
                    .init(english: "The shaded path comes back here, right?", chinese: "树荫下这条路会回到这里，对吗？", response: "你确认了返程，保留了悠闲散步而不赶路的节奏。")])],
              closing: "一次好问路，不只说目的地，也确认自己是否听懂。"),
        .init(id: "coffee", scene: .park, title: "礼貌入座", symbol: "cup.and.saucer",
              introduction: "想象你端着咖啡来到一张共用桌旁。空椅子上没有东西，但你不确定有没有人。练习一段不打扰对方的短交流。",
              steps: [
                .init(context: "桌边的人正在翻书。你想先确认座位。", question: "怎样轻轻开口？", choices: [
                    .init(english: "Excuse me, is this seat taken?", chinese: "打扰一下，这里有人坐吗？", response: "一句简短的询问，先给对方回应的空间。taken 在这里表示座位已被占用。"),
                    .init(english: "Would you mind if I sat here?", chinese: "你介意我坐在这里吗？", response: "这是更委婉的请求。对方说 Not at all，意思是完全不介意。")]),
                .init(context: "对方微笑说：Go ahead. 然后又看向书页。", question: "你准备怎样回应？", choices: [
                    .init(english: "Thanks. Enjoy your book.", chinese: "谢谢，祝你阅读愉快。", response: "你接住了善意，也尊重了对方想继续阅读的信号。"),
                    .init(english: "Thank you. I'll keep my things over here.", chinese: "谢谢，我会把东西放在这边。", response: "你说明了自己的空间边界，让共用一张桌子更轻松。")])],
              closing: "友好的交流，有时只需要一句问候和恰到好处的留白。"),
        .init(id: "journal", scene: .park, title: "随手一记", symbol: "book.closed",
              introduction: "打开手边的笔记本。不必写一整篇游记，先从一个你愿意记住的细节开始。",
              steps: [
                .init(context: "眼前有树影、桌上的地图，也有一杯暂时放下的咖啡。", question: "你的第一句想写什么？", choices: [
                    .init(english: "The trees make this place feel peaceful.", chinese: "树木让这里显得很宁静。", response: "你把景物和感受连在了一起：make this place feel peaceful。"),
                    .init(english: "I have nowhere to rush to.", chinese: "我没有什么地方需要赶着去。", response: "你记录的是这一刻的节奏。nowhere to rush to 比简单的“我很闲”更具体。")]),
                .init(context: "第一句已经落下。现在给这段小记留一个结尾。", question: "你想保留哪种感受？", choices: [
                    .init(english: "A quiet moment can be enough.", chinese: "一个安静的片刻，也已经足够。", response: "你选择不急着替这一刻寻找更大的意义。"),
                    .init(english: "I'll remember the small things.", chinese: "我会记住这些小事。", response: "你给旅行留了一个温柔的观察目标：small things。")])],
              closing: "两句短句，也能是一页完整的记忆。"),
        .init(id: "observe", scene: .pond, title: "细看倒影", symbol: "binoculars",
              introduction: "把目光借给细节，看看水波怎样改变树的轮廓。用短短两句英语，告诉同行的人你发现了什么。",
              steps: [
                .init(context: "树枝和蓝天映在水里，轮廓随着水波改变。", question: "怎样说出你注意到的细节？", choices: [
                    .init(english: "The trees are reflected in the water.", chinese: "树木倒映在水中。", response: "reflected in 描述倒映的位置；不用把倒影误说成水下生长的树。"),
                    .init(english: "The ripples keep changing the shapes.", chinese: "涟漪不断改变着那些形状。", response: "ripples 是细小的波纹，keep changing 表达持续的变化。")]),
                .init(context: "再看一会儿，你发现水面并不是一面不动的镜子。", question: "你会怎样把这个发现告诉同行的人？", choices: [
                    .init(english: "Look how the branches seem to move.", chinese: "看，树枝像是在移动。", response: "seem to 给感官印象留有余地：动的是水中的影像，不一定是树枝本身。"),
                    .init(english: "Let's watch for another moment.", chinese: "我们再看一会儿吧。", response: "你发出的是一个轻轻的邀请，而不是催促。")])],
              closing: "观察的乐趣，是为同一片风景找到更准确的词。"),
        .init(id: "sketch", scene: .pond, title: "构思速写", symbol: "pencil.and.outline",
              introduction: "翻开速写本，先为画面选择主角，再给它留出呼吸的空间。把这份构思用英语记下来。",
              steps: [
                .init(context: "本子上有一棵树的淡淡草稿。你可以关注树本身，也可以关注水里变形的轮廓。", question: "这次你想把什么作为画面的主角？", choices: [
                    .init(english: "I'll start with the shape of the tree.", chinese: "我会先从树的形状开始。", response: "你选择先建立大轮廓，让细节以后再进入画面。"),
                    .init(english: "I want to capture the reflections.", chinese: "我想捕捉这些倒影。", response: "你选择的是稍纵即逝的变化，不要求每条线都精确。")]),
                .init(context: "构图有了主角。现在决定怎样为它留出空间。", question: "你会给自己怎样的小提示？", choices: [
                    .init(english: "I'll leave some space around it.", chinese: "我会在它周围留一些空白。", response: "留白帮助视线落在主角上。around it 清楚地说明了空间关系。"),
                    .init(english: "I'll focus on a few simple lines.", chinese: "我会专注于几条简单的线。", response: "你降低了细节负担，让这次速写从可完成的小目标开始。")])],
              closing: "先决定看什么，才决定画什么。"),
        .init(id: "postcard", scene: .pond, title: "写张短笺", symbol: "envelope",
              introduction: "拿起一张空白明信片，为一个不在这里的人留两句话。短笺只保存在本机，不会寄出。",
              steps: [
                .init(context: "你想把池边这个片刻带给一个不在这里的人。", question: "第一句，想分享景色还是心情？", choices: [
                    .init(english: "I found a quiet spot by the pond.", chinese: "我在池塘边找到一个安静的角落。", response: "先交代地点，让读信的人也能想象你在哪里停下。"),
                    .init(english: "Today, I'm taking things slowly.", chinese: "今天，我在慢慢来。", response: "take things slowly 不只指脚步，也可以指放松生活的节奏。")]),
                .init(context: "把它收成一张很短、但有温度的便笺。", question: "你更想用哪一句结尾？", choices: [
                    .init(english: "I wish you could see it too.", chinese: "真希望你也能看到。", response: "你分享了一个愿望，不把它误写成已安排好的同行计划。"),
                    .init(english: "I'll tell you more when I'm back.", chinese: "等我回去，再多讲一些给你听。", response: "你为下一次相见留了一个小小的期待。")])],
              closing: "很短的一张便笺，也可以把一个片刻交给另一个人。")
    ]
}

import SwiftUI

struct UnitLearningMainlineScene: Identifiable {
    let id: Int
    let requiredCompletedLevels: Int
    let title: String
    let setup: String
    let lines: [(speaker: String, english: String, chinese: String)]
}

enum UnitLearningMainline {
    static func scenes(role: String) -> [UnitLearningMainlineScene] {
        switch role {
        case "oliver": [
            .init(id: 1, requiredCompletedLevels: 1, title: "书店角落的空白页", setup: "Oliver 邀请你试读他一直不敢拿出来的小说开头。", lines: [
                ("Oliver", "I wrote this on a rainy Tuesday. It still feels unfinished.", "我在一个下雨的星期二写了它。现在看仍觉得没写完。"),
                ("你", "A first page doesn't have to carry the whole book.", "第一页不用承载整本书。"),
                ("Oliver", "That's annoyingly sensible. Could we read one more page tomorrow?", "你说得让人没法反驳。明天能再读一页吗？"),
            ]),
            .init(id: 2, requiredCompletedLevels: 3, title: "谁来读这段故事", setup: "书店准备一次小型朗读，Oliver 担心没人愿意听。", lines: [
                ("Oliver", "The shop can fit eight people, if we move the atlas shelf.", "如果挪开地图册书架，店里能坐八个人。"),
                ("你", "Then invite eight, and leave room for someone who changes their mind.", "那就邀请八个人，也给临时改变主意的人留点空间。"),
                ("Oliver", "A reading with an empty chair. I rather like that.", "一场留着空椅子的朗读会。我挺喜欢。"),
            ]),
            .init(id: 3, requiredCompletedLevels: 6, title: "读者的不同结尾", setup: "朗读后，有读者对结尾提出相反的意见。", lines: [
                ("Oliver", "One reader wants a happy ending. Another thinks that would be dishonest.", "一个读者想要圆满结局，另一个觉得那样不诚实。"),
                ("你", "They can disagree about the ending and both care about the character.", "他们可以对结局有分歧，同时都关心这个人物。"),
                ("Oliver", "So I should listen before rewriting. That's harder than it sounds.", "所以我得先听，再修改。说起来容易。"),
            ]),
            .init(id: 4, requiredCompletedLevels: 9, title: "小说仍在继续", setup: "Oliver 把完成的章节放上书架，但没有把它当成定稿。", lines: [
                ("Oliver", "I used to call these pages unfinished as an excuse to hide them.", "我以前说它们没写完，其实是给自己找个藏起来的理由。"),
                ("你", "Now they're open to readers, and open to change.", "现在它们既可以给读者看，也还可以继续改。"),
                ("Oliver", "Exactly. Put the empty chair by the window again?", "正是。再把那把空椅子放到窗边，好吗？"),
            ]),
        ]
        case "ruby": [
            .init(id: 1, requiredCompletedLevels: 1, title: "咖啡杯上的海龟", setup: "Ruby 在咖啡馆收到一张关于海龟救助的留言。", lines: [
                ("Ruby", "Someone saw a turtle near the pier, but they didn't touch it. Good call.", "有人在码头附近看到海龟，但没碰它。这做得对。"),
                ("你", "We can note the place and ask the rescue team what to do.", "我们可以记下地点，再问救助团队怎么做。"),
                ("Ruby", "No worries. I have their number right here.", "没问题。我这里就有他们的电话。"),
            ]),
            .init(id: 2, requiredCompletedLevels: 3, title: "潮汐表与时间", setup: "救助团队邀请你们协助记录海滩情况。", lines: [
                ("Ruby", "Low tide is at four, but the team won't arrive until five.", "四点退潮，但团队五点才到。"),
                ("你", "Let's record what we see from a safe distance and wait for them.", "我们先在安全距离记录观察，再等他们。"),
                ("Ruby", "Exactly. Helping doesn't mean rushing in.", "正是。帮忙不等于冲上去。"),
            ]),
            .init(id: 3, requiredCompletedLevels: 6, title: "一张不完整的记录表", setup: "一周观察后，Ruby 发现记录里的空白比数字更多。", lines: [
                ("Ruby", "We saw two turtles, but we missed three days of observations.", "我们看到了两只海龟，但有三天没有观察记录。"),
                ("你", "Then the report should say what we know and what we don't.", "报告就该写清楚我们知道什么、不知道什么。"),
                ("Ruby", "That's science. Honest gaps are better than invented certainty.", "这才是科学。坦诚的空白比编造的确定性好。"),
            ]),
            .init(id: 4, requiredCompletedLevels: 9, title: "把海岸交给更多双眼睛", setup: "Ruby 准备把观察方式教给新的志愿者。", lines: [
                ("Ruby", "A good guide must be clear enough for someone who's never been here.", "好的指南应让从没来过的人也能看懂。"),
                ("你", "Let's explain the safe distance first, then show how to record time and place.", "先讲安全距离，再教怎么记录时间地点。"),
                ("Ruby", "Heaps good. We can help without making ourselves the heroes of the story.", "太好了。我们能帮忙，也不必把自己当成故事主角。"),
            ]),
        ]
        case "marcus": [
            .init(id: 1, requiredCompletedLevels: 1, title: "底片里的陌生人", setup: "Marcus 冲洗出一张很喜欢的街头照片，却停在了是否展示这一步。", lines: [
                ("Marcus", "The light is perfect, but that person didn't ask to be in my show.", "光线完美，可照片里的人并没有答应进我的展览。"),
                ("你", "We could ask before we put it on the wall.", "挂上墙前，我们可以先征求同意。"),
                ("Marcus", "For real. A good picture isn't a free pass.", "真的。照片拍得好，不等于可以随便用。"),
            ]),
            .init(id: 2, requiredCompletedLevels: 3, title: "展览的第一张说明牌", setup: "同意展示的人想让观众知道照片背后的日常。", lines: [
                ("Marcus", "She says the shop opened before sunrise because her father worked nights.", "她说店在日出前开门，是因为她父亲上夜班。"),
                ("你", "Let's use her words, and check the caption with her.", "用她自己的话写说明，再请她确认。"),
                ("Marcus", "Good. Her story, her say.", "好。她的故事，她说了算。"),
            ]),
            .init(id: 3, requiredCompletedLevels: 6, title: "两张相反的城市照片", setup: "观众对街道的变化提出不同看法。", lines: [
                ("Marcus", "One photo shows a crowded market. Another shows an empty street after dark.", "一张照片是拥挤的市场，另一张是天黑后的空街。"),
                ("你", "Both are true moments. Neither can stand for the whole neighborhood.", "两个瞬间都是真的，但都不能代表整个社区。"),
                ("Marcus", "No cap. Let's hang them together and let people talk.", "真的。把它们放在一起，让大家谈谈。"),
            ]),
            .init(id: 4, requiredCompletedLevels: 9, title: "城市的手", setup: "Marcus 的第一场小型影展终于开放。", lines: [
                ("Marcus", "I called it The City's Hands, but the captions name the people too.", "我把展览叫《城市的手》，但说明牌也写出了每个人的名字。"),
                ("你", "The city is made by them, not by your camera alone.", "这座城市由他们构成，不只是由你的相机呈现。"),
                ("Marcus", "That's the picture I was trying to take all along.", "这才是我一直想拍到的画面。"),
            ]),
        ]
        default: []
        }
    }
}

struct UnitLearningMainlineView: View {
    let scene: UnitLearningMainlineScene
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(scene.title).font(.largeTitle.bold())
                Text(scene.setup).foregroundStyle(.secondary)
                ForEach(scene.lines.indices, id: \.self) { index in
                    let line = scene.lines[index]
                    VStack(alignment: .leading, spacing: 6) {
                        Text(line.speaker).font(.caption.bold()).foregroundStyle(.teal)
                        Text(line.english).font(.body)
                        Text(line.chinese).font(.footnote).foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .padding(20)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("学习主线")
        .navigationBarTitleDisplayMode(.inline)
    }
}

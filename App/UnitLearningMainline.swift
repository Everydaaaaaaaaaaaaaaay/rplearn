import SwiftUI

struct UnitLearningMainlineScene: Identifiable {
    let id: Int
    let requiredCompletedLevels: Int
    let title: String
    let setup: String
    let lines: [(speaker: String, english: String, chinese: String)]
}

/// 全账号只有一条主线；章节由挑战取得的真实升级次数解锁，手动改级不会推进剧情。
enum UnitLearningMainline {
    static let scenes: [UnitLearningMainlineScene] = [
        .init(id: 0, requiredCompletedLevels: 0, title: "空白的第一页", setup: "向导 Mira 交给你一本空白旅行册，邀请你一起为后来者写指南。", lines: [
            ("Mira", "Hello! I'm Mira. What's your name?", "你好！我是 Mira。你叫什么名字？"),
            ("你", "I'm ready to begin.", "我准备好出发了。"),
            ("Mira", "Good. A journey starts with a hello.", "很好。一段旅程从一句问候开始。"),
        ]),
        .init(id: 1, requiredCompletedLevels: 1, title: "第一张路标", setup: "你们发现车站的指示牌褪了色，第一次尝试给陌生人指路。", lines: [
            ("旅人", "Where is the library?", "图书馆在哪里？"),
            ("你", "Go straight. It's next to the park.", "直走。它就在公园旁边。"),
            ("Mira", "Let's draw the park too. A clear map helps more than one person.", "把公园也画上吧。清楚的地图能帮助更多人。"),
        ]),
        .init(id: 2, requiredCompletedLevels: 2, title: "谁需要这张地图", setup: "一位带着孩子的旅人看不懂你们画的路线。", lines: [
            ("旅人", "My daughter can't walk far. Is there a shorter way?", "我女儿走不了太远。有更近的路吗？"),
            ("你", "The small gate is near the bus stop.", "小门靠近公交站。"),
            ("Mira", "Our first map missed that. Let's add the gate and the bus stop.", "第一张地图漏掉了这点。把小门和公交站加上。"),
        ]),
        .init(id: 3, requiredCompletedLevels: 3, title: "错过的末班车", setup: "旧时刻表让一位旅人错过了回程车。", lines: [
            ("旅人", "The sign says six, but the last bus left at five thirty.", "牌子写六点，但末班车五点半就走了。"),
            ("你", "Let's check the new timetable before we change the guide.", "先核对新时刻表，再修改指南。"),
            ("Mira", "And write the date. A useful fact can become an old fact.", "还要写上日期。有用的信息也会过时。"),
        ]),
        .init(id: 4, requiredCompletedLevels: 4, title: "两条都正确的路", setup: "有人想省时间，也有人需要轮椅可通行的路线。", lines: [
            ("Mira", "The bridge is faster, but it has stairs. The riverside path has a ramp.", "过桥更快，但有台阶；河边路有坡道。"),
            ("你", "Let's show both routes and explain who each one helps.", "两条路线都标出来，说明各适合谁。"),
            ("Mira", "A guide should offer a choice, not pretend one answer fits everyone.", "指南应给人选择，不该假装一种答案适合所有人。"),
        ]),
        .init(id: 5, requiredCompletedLevels: 5, title: "邀请函上的空格", setup: "社区邀请你们展示旅行册，但时间和地点仍未确定。", lines: [
            ("志愿者", "Can you send the invitation today? People want to plan ahead.", "今天能发邀请吗？大家想提前安排。"),
            ("你", "We can announce the event, but we must mark the time as unconfirmed.", "可以先预告活动，但必须注明时间未确定。"),
            ("Mira", "Then we will update everyone once the hall is booked.", "等场地订好，我们再通知大家。"),
        ]),
        .init(id: 6, requiredCompletedLevels: 6, title: "没有写下来的声音", setup: "展示会上，一位居民指出指南只记录了游客的经验。", lines: [
            ("居民", "Your guide calls this street quiet. It isn't quiet for the people who work here at dawn.", "指南说这条街很安静。对黎明就在这里工作的人来说并非如此。"),
            ("你", "We described one visit as if it were true all day. Could we hear your account?", "我们把一次走访写成了全天情况。能听听您的经历吗？"),
            ("Mira", "We'll keep the earlier note, add its time, and make room for another voice.", "保留先前记录，注明时间，也给另一种声音留位置。"),
        ]),
        .init(id: 7, requiredCompletedLevels: 7, title: "两份相反的记录", setup: "新旧观察记录对同一条街的变化给出了不同判断。", lines: [
            ("Mira", "One survey says the market is busier; another says fewer shops are open. Can both be true?", "一份调查说市场更热闹，另一份说开门的店更少。两者可能都对吗？"),
            ("你", "Yes. More visitors could be using fewer shops. We need dates and counts before claiming a trend.", "可能。更多访客也许集中在更少的店里。下结论前得核对日期和数量。"),
            ("Mira", "Let's publish the question alongside the evidence, not hide it.", "把疑问连同证据一起呈现，不要藏起来。"),
        ]),
        .init(id: 8, requiredCompletedLevels: 8, title: "照片里的人", setup: "一张照片能让指南更生动，但照片中的人尚未同意公开。", lines: [
            ("摄影者", "The image tells the story better than any paragraph. May I upload it?", "这张照片比文字更能讲故事。我能上传吗？"),
            ("你", "Ask the people in it first. If they decline, we can describe the scene without showing their faces.", "先问照片里的人。如果他们不同意，我们可以只描述场景，不展示面孔。"),
            ("Mira", "A compelling story doesn't cancel someone's right to choose.", "故事再动人，也不能取消别人选择的权利。"),
        ]),
        .init(id: 9, requiredCompletedLevels: 9, title: "地图边界上的争论", setup: "新版路线会带来客流，也可能打扰附近居民。", lines: [
            ("店主", "The new route could help small shops survive.", "新路线可能帮助小店生存。"),
            ("居民", "It could also send visitors past our homes late at night.", "也可能让游客深夜经过我们的住处。"),
            ("你", "We'll compare daytime benefits with evening costs, then ask both groups to review the wording.", "我们会比较白天的收益与夜间的代价，再请双方核对措辞。"),
        ]),
        .init(id: 10, requiredCompletedLevels: 10, title: "写给还没到来的人", setup: "指南开始面向不同语言背景和出行需要的读者。", lines: [
            ("Mira", "A visitor may read this in a hurry, on a small screen, with no local knowledge.", "访客可能在匆忙中，用小屏幕阅读，而且不熟悉当地。"),
            ("你", "Then each instruction needs a clear action, a landmark, and a way to check whether it is still current.", "那每条指引都需要明确动作、地标，以及核对时效的办法。"),
            ("Mira", "Let's ask new readers to test it before we call it finished.", "在称它完成之前，请新读者试用。"),
        ]),
        .init(id: 11, requiredCompletedLevels: 11, title: "仍然空白的最后一页", setup: "旅行册终于出版。Mira 却留下一页空白，等你决定如何继续。", lines: [
            ("Mira", "We corrected routes, checked claims, and listened when people disagreed. This edition will still grow old.", "我们修正路线、核实说法，也在意见不同时认真倾听。但这一版仍会过时。"),
            ("你", "Then the last page should explain how readers can question us and help improve the next one.", "那最后一页应该告诉读者如何提出疑问、帮助改进下一版。"),
            ("Mira", "Exactly. Learning is not a final page. It's the habit of returning with better questions.", "正是。学习没有最后一页，它是带着更好的问题继续回来。"),
        ]),
    ]
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
        .navigationTitle("主线剧情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

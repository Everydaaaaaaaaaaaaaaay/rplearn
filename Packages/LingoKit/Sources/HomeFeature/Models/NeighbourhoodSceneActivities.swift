import Foundation

extension SceneActivity {
    static let bookstallCatalog: [Self] = [
        .init(id: "bookstall-cover", scene: .bookstall, title: "同翻一页", symbol: "book",
              introduction: "旧书摊边，你和另一位客人留意到同一摞书。先聊封面，不必考验彼此读过多少。",
              steps: [
                .init(context: "你刚把一本书放回书堆，旁边的客人也停下来看看。对方没有在阅读或打电话。",
                      question: "你想从哪里开始聊？", choices: [
                        .init(english: "What caught your eye about this book?", chinese: "这本书的什么地方吸引了你？",
                              response: "catch your eye 表示吸引目光，比直接询问读后感更容易接话。"),
                        .init(english: "Are you browsing, or looking for something in particular?", chinese: "你随便看看，还是在找某一本书？",
                              response: "just browsing 是随便看看；in particular 表示特定的，不预设对方是书迷。")]), farewell],
              closing: "同一本书，可以通向完全不同的故事。"),
        .init(id: "bookstall-recommend", scene: .bookstall, title: "交换推荐", symbol: "text.bubble",
              introduction: "书列旁，一位客人刚结束浏览。你们短暂对上目光，可以交换一点阅读偏好。",
              steps: [
                .init(context: "对方把书放回右侧的小书堆，给你腾出位置。你想问问有没有值得一看的书。",
                      question: "怎样问得轻松一点？", choices: [
                        .init(english: "Have you read anything good lately?", chinese: "你最近读到什么不错的书了吗？",
                              response: "anything good 是开放的问法；对方也可以说最近没有读书，不需要硬给推荐。"),
                        .init(english: "What do you usually enjoy reading?", chinese: "你平时喜欢读些什么？",
                              response: "enjoy reading 可以包括小说、漫画和文章，不把阅读局限在某一类书。")]), farewell],
              closing: "交换推荐，不需要拥有相同的喜好。"),
        .init(id: "bookstall-travel", scene: .bookstall, title: "聊聊见闻", symbol: "leaf",
              introduction: "摊开的插图书里画着常见的花草。另一位客人也停下看看，你想从一次出门的见闻聊起。",
              steps: [
                .init(context: "你指向书中的花草插图，对方也笑着看了一眼。先聊出门时的发现，不追问住址或行程。",
                      question: "哪一种开场更适合你？", choices: [
                        .init(english: "Does this remind you of anywhere?", chinese: "这里让你想到什么地方吗？",
                              response: "remind you of… 表示让你想起，不要求对方去过图中的地点。"),
                        .init(english: "Do you prefer city walks or the countryside?", chinese: "你更喜欢在城市散步，还是到乡间走走？",
                              response: "prefer 是更喜欢；可以说 neither 或 both，不必局限于给出的两种选择。")]), farewell],
              closing: "一张插图，也可以打开一段不同的生活。")
    ]

    static let flowerstallCatalog: [Self] = [
        .init(id: "flowerstall-colour", scene: .flowerstall, title: "聊聊花色", symbol: "camera.macro",
              introduction: "花桶旁，你和另一位客人都停下来看看。聊一种颜色就好，不需要懂园艺。",
              steps: [
                .init(context: "对方看了看粉色和白色郁金香，又向旁边让出一点位置。你们有片刻不赶时间的空当。",
                      question: "你想从哪一句开始？", choices: [
                        .init(english: "Which colour would you go for?", chinese: "你会选哪种颜色？",
                              response: "go for 在这里是选择，适合轻松地交换偏好，不是在询问专业知识。"),
                        .init(english: "These really brighten up the street, don't they?", chinese: "这些花真让街道亮起来了，你说呢？",
                              response: "brighten up 可以表示增添亮色或让心情变好；句尾轻轻邀请对方回应。")]), farewell],
              closing: "喜欢不同的颜色，也能聊得来。"),
        .init(id: "flowerstall-bouquet", scene: .flowerstall, title: "一束心意", symbol: "gift",
              introduction: "包装好的花束旁，一位客人也在挑选。可以聊日常的小心意，不猜测对方的关系或送花对象。",
              steps: [
                .init(context: "你看了看黄色花束，对方停下脚步。你想聊聊给普通一天添一点仪式感。",
                      question: "你想怎样打开话题？", choices: [
                        .init(english: "Do you ever buy flowers just for yourself?", chinese: "你会专门给自己买花吗？",
                              response: "just for yourself 指单纯为了自己，不默认买花就是送给恋人。"),
                        .init(english: "It's nice to make an ordinary day feel special.", chinese: "让普通的一天变得特别一点，感觉挺好。",
                              response: "make… feel special 表示让某人或某一天显得特别，是分享想法而非盘问。")]), farewell],
              closing: "一份心意，可以留给自己，也可以送给别人。"),
        .init(id: "flowerstall-queue", scene: .flowerstall, title: "等候闲聊", symbol: "bubble.left.and.bubble.right",
              introduction: "包装区旁，摊主正在整理一束花。你先确认谁在等候，再看看旁边的人是否愿意聊两句。",
              steps: [
                .init(context: "包装纸和棉线放在台面上，一位客人刚收好手机。你站在一旁，不打断摊主手上的工作。",
                      question: "你会怎样确认？", choices: [
                        .init(english: "Excuse me, are you waiting to be served?", chinese: "打扰一下，你正在等店员接待吗？",
                              response: "waiting to be served 是等候接待，适用于没有明显队伍的小摊或店铺。"),
                        .init(english: "Is this the end of the queue?", chinese: "这里是队尾吗？",
                              response: "the end of the queue 指队尾；确认之后留出通道，不挤到别人前面。")]), farewell],
              closing: "短短的等候，也可以交换一句有温度的话。")
    ]
}

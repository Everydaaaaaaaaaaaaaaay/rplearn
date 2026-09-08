import Foundation

extension SceneActivity {
    static let pondCatalog: [Self] = [
        .init(id: "pond-reflection", scene: .pond, title: "看看倒影", symbol: "binoculars",
              introduction: "双筒望远镜放在石台上。你和旁边的人都在看水面的树影，可以从刚刚发现的变化聊起。",
              steps: [
                .init(context: "水波把树枝的轮廓轻轻打散，对方也顺着你的视线看过去。",
                      question: "怎样邀请对方一起看？", choices: [
                        .init(english: "Have you noticed how the reflections keep changing?", chinese: "你注意到倒影一直在变化吗？",
                              response: "Have you noticed… 是分享观察，不是在测试对方有没有认真看。"),
                        .init(english: "The water makes the branches seem to move, doesn't it?", chinese: "水面让树枝看起来像在动，对吧？",
                              response: "seem to 表示看起来如此，准确地区分了树枝和倒影。")]),
                farewell],
              closing: "同看一片水面，也能发现不一样的细节。"),
        .init(id: "pond-sketch", scene: .pond, title: "聊聊速写", symbol: "pencil.and.outline",
              introduction: "速写本翻在一页淡淡的草图上。你可以向同样停下来观察的人聊聊构图，不必假设对方会画画。",
              steps: [
                .init(context: "你在树的轮廓和水中的倒影之间犹豫，对方刚好看了一眼本子。",
                      question: "你想怎样把话题交给对方？", choices: [
                        .init(english: "Would you start with the tree or its reflection?", chinese: "你会先画树，还是先画它的倒影？",
                              response: "would you start with 是轻松的设想，即使对方不画画也可以回答。"),
                        .init(english: "I'm trying to keep this sketch simple.", chinese: "我想让这张速写保持简单。",
                              response: "trying to 分享自己的过程，为对方留下回应或继续观察的空间。")]),
                farewell],
              closing: "聊构图，不需要先证明谁更懂画画。"),
        .init(id: "pond-postcard", scene: .pond, title: "写张短笺", symbol: "envelope",
              introduction: "几张明信片放在石台边。你想写一句池畔见闻，也可以问问身旁的人哪种表达更自然。",
              steps: [
                .init(context: "你写下开头，又停下来看看水面。旁边的人没有在打电话或忙着离开。",
                      question: "怎样自然地请对方给一点意见？", choices: [
                        .init(english: "Does ‘a quiet spot by the pond’ sound natural?", chinese: "“池塘边一个安静的角落”这样说自然吗？",
                              response: "sound natural 是请对方判断表达是否自然，不要求对方替你写完整张卡片。"),
                        .init(english: "What small detail would you put on a postcard?", chinese: "你会把哪个小细节写进明信片？",
                              response: "small detail 把话题留在共同看见的场景里，不追问私人收件人。")]),
                farewell],
              closing: "一张短笺，也可以从两个人共同看见的细节开始。")
    ]

    static let rainCafeCatalog: [Self] = [
        .init(id: "rain-weather", scene: .raincafe, title: "聊聊雨天", symbol: "cloud.rain",
              introduction: "雨水沿着窗面落下。你和同桌的人都望向窗外，可以从天气轻轻聊起。",
              steps: [
                .init(context: "一阵雨声盖过了店里的背景声，对方也转头看了看窗外。",
                      question: "怎样开启这个话题？", choices: [
                        .init(english: "Do you enjoy watching the rain from somewhere warm?", chinese: "你喜欢待在温暖的地方看雨吗？",
                              response: "from somewhere warm 说的是当下体验，不预设对方喜欢淋雨或讨厌雨天。"),
                        .init(english: "It feels like a good day to slow down, doesn't it?", chinese: "今天好像很适合慢下来，对吧？",
                              response: "feels like 表达个人感受，句尾给对方轻松回应的机会。")]),
                farewell],
              closing: "窗外的雨没有停，短短的话题已经让等待变得不一样。"),
        .init(id: "rain-pastry", scene: .raincafe, title: "分享点心", symbol: "fork.knife",
              introduction: "左侧盘里有几块点心。先确认对方是否愿意，再把分享变成一次不带压力的邀请。",
              steps: [
                .init(context: "点心盘放在桌边，对方看了一眼，但你不知道对方的口味或饮食习惯。",
                      question: "怎样问得体贴一些？", choices: [
                        .init(english: "Would you like to try one of these?", chinese: "你想尝一块吗？",
                              response: "Would you like… 是提供选择；对方拒绝时不需要追问原因。"),
                        .init(english: "Please help yourself if you'd like one.", chinese: "如果你想吃，请随意拿一块。",
                              response: "help yourself 表示请自取，if 保留了不吃的选择。")]),
                farewell],
              closing: "分享食物之前先给选择，善意才不会变成压力。"),
        .init(id: "rain-napkin", scene: .raincafe, title: "递张纸巾", symbol: "rectangle.stack",
              introduction: "桌边的纸巾就在手边。雨水和热饮让一个小小的帮忙显得自然，但仍先问一句。",
              steps: [
                .init(context: "对方刚收起被雨打湿的随身物品，桌边的纸巾离你更近。",
                      question: "怎样提供帮助而不显得冒失？", choices: [
                        .init(english: "Would you like a napkin?", chinese: "你需要一张纸巾吗？",
                              response: "简短询问先确认需要，再伸手递过去。"),
                        .init(english: "The napkins are right here if you need one.", chinese: "如果你需要，纸巾就在这里。",
                              response: "if you need one 让对方自行决定，也清楚指出物品位置。")]),
                farewell],
              closing: "一次恰到好处的小帮助，也可以成为自然的开场。")
    ]
}

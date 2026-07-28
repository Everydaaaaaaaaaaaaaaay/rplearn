/// 一座城市独立于主线的在地故事。首次抵达城市后解锁，并需在当地开展。
public struct CityStoryChapter: Sendable, Equatable, Hashable, Identifiable {
    public let storyID: String
    public let regionID: String
    public let title: String
    public let subtitle: String

    public var id: String { storyID }

    public init(storyID: String, regionID: String, title: String, subtitle: String) {
        self.storyID = storyID
        self.regionID = regionID
        self.title = title
        self.subtitle = subtitle
    }
}

public enum CityStoryCatalog {
    /// 顺序与地区目录一致，便于产品配置和完整性检查。
    public static let chapters: [CityStoryChapter] = [
        CityStoryChapter(
            storyID: "mainline_london_2",
            regionID: "london",
            title: "酒馆问答之夜",
            subtitle: "跟着 Oliver 参加一场兵荒马乱的 pub quiz"
        ),
        CityStoryChapter(
            storyID: "mainline_melbourne_2",
            regionID: "melbourne",
            title: "从豆子到一杯",
            subtitle: "和 Ruby 烘一炉咖啡，拉第一杯 flat white"
        ),
        CityStoryChapter(
            storyID: "mainline_newyork_2",
            regionID: "newyork",
            title: "地铁里的肖像",
            subtitle: "Marcus 教你用尊重换来一张真实的照片"
        ),
        CityStoryChapter(
            storyID: "city_capetown",
            regionID: "capetown",
            title: "博卡普的调色课",
            subtitle: "帮街坊为一面褪色的墙找回属于社区的颜色"
        ),
        CityStoryChapter(
            storyID: "city_singapore",
            regionID: "singapore",
            title: "熟食中心的空桌",
            subtitle: "在一张共享餐桌上，学会这座城市最自然的问候"
        ),
        CityStoryChapter(
            storyID: "city_dublin",
            regionID: "dublin",
            title: "长厅遗失的书签",
            subtitle: "沿着手写诗句，把一枚旧书签送回故事的主人"
        ),
        CityStoryChapter(
            storyID: "city_edinburgh",
            regionID: "edinburgh",
            title: "皇家一英里的最后一场",
            subtitle: "在雨落之前，帮街头演员找回消失的结尾"
        ),
        CityStoryChapter(
            storyID: "city_vancouver",
            regionID: "vancouver",
            title: "海堤上的失物",
            subtitle: "骑过森林与海湾，为一台旧相机寻找主人"
        ),
        CityStoryChapter(
            storyID: "city_auckland",
            regionID: "auckland",
            title: "风帆之城的口令",
            subtitle: "加入临时船队，用清楚的英语把大家带回港湾"
        ),
        CityStoryChapter(
            storyID: "city_nairobi",
            regionID: "nairobi",
            title: "卡鲁拉森林的雨",
            subtitle: "一场骤雨打乱路线，也让陌生人组成了小队"
        ),
        CityStoryChapter(
            storyID: "city_toronto",
            regionID: "toronto",
            title: "地下城的方向暗号",
            subtitle: "在 PATH 的岔路间，用清楚的问题带陌生人找到出口"
        ),
        CityStoryChapter(
            storyID: "city_sydney",
            regionID: "sydney",
            title: "海风里的失物广播",
            subtitle: "赶在渡轮离港前，用准确描述送回一本旅行笔记"
        ),
        CityStoryChapter(
            storyID: "city_neworleans",
            regionID: "neworleans",
            title: "爵士街角的下一小节",
            subtitle: "先听懂乐手的邀请，再为临时演出接上新的节拍"
        ),
        CityStoryChapter(
            storyID: "city_manchester",
            regionID: "manchester",
            title: "雨夜唱片的 A 面",
            subtitle: "在北区唱片店打烊前，替一首无名录音找到线索"
        ),
        CityStoryChapter(
            storyID: "city_kingston",
            regionID: "kingston",
            title: "录音棚里缺失的开场",
            subtitle: "听懂金斯敦自己的语言节奏，为社区节目补上第一句话"
        ),
    ]

    public static func chapter(forRegion regionID: String) -> CityStoryChapter? {
        chapters.first { $0.regionID == regionID }
    }
}

/// 一座城市独立于主线的生活故事。解锁后可从任意位置直接开展。
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
    /// 城市剧情不再绑定到访状态：前六篇默认开放，之后每累计一张机票开放三篇。
    public static let defaultUnlockedChapterCount = 6
    public static let chaptersPerTicket = 3

    /// 顺序与地区目录一致，便于产品配置和完整性检查。
    public static let chapters: [CityStoryChapter] = [
        CityStoryChapter(
            storyID: "departures_city_london_v1",
            regionID: "london",
            title: "退回书架的那一本",
            subtitle: "一本人人称赞的书，你却读不下去。"
        ),
        CityStoryChapter(
            storyID: "departures_city_melbourne_v1",
            regionID: "melbourne",
            title: "不下海的早晨",
            subtitle: "期待已久的冲浪日，没有按照片里的样子到来。"
        ),
        CityStoryChapter(
            storyID: "departures_city_newyork_v1",
            regionID: "newyork",
            title: "等你吃饭的十分钟",
            subtitle: "约好的午餐被工作打断，两个人都不想显得难相处。"
        ),
        CityStoryChapter(
            storyID: "departures_city_capetown_v1",
            regionID: "capetown",
            title: "借你半张桌子",
            subtitle: "集市开张前，Amina 的摊位比想象中更挤。"
        ),
        CityStoryChapter(
            storyID: "departures_city_singapore_v1",
            regionID: "singapore",
            title: "打包的另一份",
            subtitle: "一份顺手的好意，也需要先问一句。"
        ),
        CityStoryChapter(
            storyID: "departures_city_dublin_v1",
            regionID: "dublin",
            title: "重录之前",
            subtitle: "Niamh 想给远方的妹妹留一句生日祝福。"
        ),
        CityStoryChapter(
            storyID: "departures_city_edinburgh_v1",
            regionID: "edinburgh",
            title: "只剩一张票",
            subtitle: "Isla 手上有一张退票，你们却有两个人。"
        ),
        CityStoryChapter(
            storyID: "departures_city_vancouver_v1",
            regionID: "vancouver",
            title: "慢一点的那条路",
            subtitle: "Noah 想拍到日落，也想让这次散步真正属于同行的人。"
        ),
        CityStoryChapter(
            storyID: "departures_city_auckland_v1",
            regionID: "auckland",
            title: "工具箱归还之前",
            subtitle: "Hana 借出了一把工具，却收到了一个更大的请求。"
        ),
        CityStoryChapter(
            storyID: "departures_city_nairobi_v1",
            regionID: "nairobi",
            title: "最后一块布",
            subtitle: "一块不够大的布料，把原本确定的设计变成了讨论。"
        ),
        CityStoryChapter(
            storyID: "departures_city_toronto_v1",
            regionID: "toronto",
            title: "谁带了主菜",
            subtitle: "Maya 的聚餐收到了三份甜点，还有一份没人敢问的沉默。"
        ),
        CityStoryChapter(
            storyID: "departures_city_sydney_v1",
            regionID: "sydney",
            title: "多坐一站",
            subtitle: "轮渡快到了，你们对“顺便走走”的理解却不一样。"
        ),
        CityStoryChapter(
            storyID: "departures_city_neworleans_v1",
            regionID: "neworleans",
            title: "点歌纸上的一行字",
            subtitle: "Calvin 收到的点歌没有歌名，只有一个说不清的心情。"
        ),
        CityStoryChapter(
            storyID: "departures_city_manchester_v1",
            regionID: "manchester",
            title: "你会留下哪一面",
            subtitle: "Leah 的新唱片让两位朋友听出了完全不同的东西。"
        ),
        CityStoryChapter(
            storyID: "departures_city_kingston_v1",
            regionID: "kingston",
            title: "节目末尾的名字",
            subtitle: "Aaliyah 的节目超时了，最容易剪掉的是别人的名字。"
        ),
    ]

    public static func chapter(forRegion regionID: String) -> CityStoryChapter? {
        chapters.first { $0.regionID == regionID }
    }

    public static func unlockedChapterCount(earnedTicketCount: Int) -> Int {
        min(
            chapters.count,
            defaultUnlockedChapterCount + max(0, earnedTicketCount) * chaptersPerTicket
        )
    }

    public static func requiredTicketCount(forChapterAt index: Int) -> Int {
        guard index >= defaultUnlockedChapterCount else { return 0 }
        return (index - defaultUnlockedChapterCount) / chaptersPerTicket + 1
    }
}

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
            subtitle: "书签停在第十九页，推荐这本书的人也没读远。"
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
            subtitle: "午饭已经凉了，说好十分钟的人还没到。"
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
            subtitle: "父亲想解除和那份鸡饭的终身合同。"
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
            subtitle: "Noah 追日落，Ruth 等一只迟迟不动的苍鹭。"
        ),
        CityStoryChapter(
            storyID: "departures_city_auckland_v1",
            regionID: "auckland",
            title: "工具箱回到桌上",
            subtitle: "借走的工具回来了，还附带一只卡住的抽屉。"
        ),
        CityStoryChapter(
            storyID: "departures_city_nairobi_v1",
            regionID: "nairobi",
            title: "最后一块布",
            subtitle: "蓝布不够，原来的设计还舍不得放下。"
        ),
        CityStoryChapter(
            storyID: "departures_city_toronto_v1",
            regionID: "toronto",
            title: "谁带了主菜",
            subtitle: "三份蛋糕，一顿还没着落的晚饭。"
        ),
        CityStoryChapter(
            storyID: "departures_city_sydney_v1",
            regionID: "sydney",
            title: "多坐一站",
            subtitle: "一条毛巾、一座海港泳池，和一小时后的电话。"
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
            subtitle: "同一张唱片，你想留下的，Leah 正准备剪掉。"
        ),
        CityStoryChapter(
            storyID: "departures_city_kingston_v1",
            regionID: "kingston",
            title: "节目末尾的名字",
            subtitle: "节目超了三十秒，Aaliyah 舍不得自己的笑话。"
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

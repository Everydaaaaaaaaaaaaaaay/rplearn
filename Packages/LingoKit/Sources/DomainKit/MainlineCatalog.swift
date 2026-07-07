/// 主线剧情章节目录：地区 → 章节脚本。
public struct MainlineChapter: Sendable, Equatable, Hashable, Identifiable {
    public var storyID: String
    public var regionID: String
    public var title: String
    public var subtitle: String

    public var id: String { storyID }

    public init(storyID: String, regionID: String, title: String, subtitle: String) {
        self.storyID = storyID
        self.regionID = regionID
        self.title = title
        self.subtitle = subtitle
    }
}

public enum MainlineCatalog {
    public static let chapters: [MainlineChapter] = [
        MainlineChapter(
            storyID: "mainline_london",
            regionID: "london",
            title: "第一章 · 雨中的书店",
            subtitle: "Oliver 的二手书店里藏着一个秘密"
        ),
        MainlineChapter(
            storyID: "mainline_melbourne",
            regionID: "melbourne",
            title: "第一章 · 清晨的海",
            subtitle: "Ruby 拉你去看日出，还有一个意外的访客"
        ),
        MainlineChapter(
            storyID: "mainline_newyork",
            regionID: "newyork",
            title: "第一章 · 快门与地铁",
            subtitle: "跟着 Marcus 的镜头，读懂这座城市"
        ),
    ]

    public static func chapters(forRegion regionID: String) -> [MainlineChapter] {
        chapters.filter { $0.regionID == regionID }
    }
}

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

/// 一条主线中的必经城市。完成前一站后才会开放下一站。
public struct MainlineStop: Sendable, Equatable, Hashable, Identifiable {
    public let chapter: MainlineChapter
    public let objective: String

    public var id: String { chapter.id }
    public var regionID: String { chapter.regionID }

    public init(chapter: MainlineChapter, objective: String) {
        self.chapter = chapter
        self.objective = objective
    }
}

/// 由初始伙伴决定的主线路线。城市集合一致，前期顺序与角色相遇顺序不同。
public struct MainlineJourney: Sendable, Equatable, Identifiable {
    public let id: String
    public let starterRegionID: String
    public let title: String
    public let stops: [MainlineStop]
    public let postStoryRegionIDs: [String]

    public init(
        id: String,
        starterRegionID: String,
        title: String,
        stops: [MainlineStop],
        postStoryRegionIDs: [String]
    ) {
        self.id = id
        self.starterRegionID = starterRegionID
        self.title = title
        self.stops = stops
        self.postStoryRegionIDs = postStoryRegionIDs
    }
}

/// 地图底部引导所需的业务状态。UI 只负责把地区数组排成单卡、双卡或多卡。
public enum JourneyMapGuidance: Sendable, Equatable, Hashable {
    case travel(
        eyebrow: String,
        title: String,
        detail: String,
        regionIDs: [String]
    )
    case continueStory(chapter: MainlineChapter, objective: String)
    case complete(title: String, detail: String)

    public var destinationRegionIDs: [String] {
        guard case .travel(_, _, _, let regionIDs) = self else { return [] }
        return regionIDs
    }
}

public enum MainlineCatalog {
    public static let london = MainlineChapter(
        storyID: "mainline_london",
        regionID: "london",
        title: "第一章 · 雨中的书店",
        subtitle: "一本旧旅行札记，留下跨越五座城市的第一条回声"
    )
    public static let melbourne = MainlineChapter(
        storyID: "mainline_melbourne",
        regionID: "melbourne",
        title: "第一章 · 清晨的海",
        subtitle: "Ruby 在潮汐里发现了来自另一片海岸的录音"
    )
    public static let newYork = MainlineChapter(
        storyID: "mainline_newyork",
        regionID: "newyork",
        title: "第一章 · 快门与地铁",
        subtitle: "Marcus 的旧胶片拍下了同一个神秘的罗盘符号"
    )
    public static let capeTown = MainlineChapter(
        storyID: "mainline_capetown",
        regionID: "capetown",
        title: "第二章 · 信号山的回声",
        subtitle: "把三条线索带到桌山脚下，听见跨越海洋的广播"
    )
    public static let singapore = MainlineChapter(
        storyID: "mainline_singapore",
        regionID: "singapore",
        title: "终章 · 雨林里的频率",
        subtitle: "在新加坡拼合声音地图，决定它下一次被谁听见"
    )

    public static let chapters: [MainlineChapter] = [
        london,
        melbourne,
        newYork,
        capeTown,
        singapore,
    ]

    public static let journeys: [MainlineJourney] = [
        journey(
            id: "echoes-oliver",
            starterRegionID: "london",
            title: "旧书中的声音地图",
            characterOrder: [london, newYork, melbourne],
            postStoryRegionIDs: ["dublin", "edinburgh", "manchester", "toronto"]
        ),
        journey(
            id: "echoes-ruby",
            starterRegionID: "melbourne",
            title: "潮汐送来的声音地图",
            characterOrder: [melbourne, london, newYork],
            postStoryRegionIDs: ["auckland", "sydney", "vancouver", "nairobi"]
        ),
        journey(
            id: "echoes-marcus",
            starterRegionID: "newyork",
            title: "胶片里的声音地图",
            characterOrder: [newYork, melbourne, london],
            postStoryRegionIDs: ["neworleans", "kingston", "toronto", "manchester"]
        ),
    ]

    public static func chapters(forRegion regionID: String) -> [MainlineChapter] {
        chapters.filter { $0.regionID == regionID }
    }

    public static func journey(starterRegionID: String?) -> MainlineJourney {
        journeys.first { $0.starterRegionID == starterRegionID } ?? journeys[0]
    }

    public static func mapGuidance(
        starterRegionID: String?,
        currentRegionID: String,
        completedStoryIDs: Set<String>,
        unlockedRegionIDs: Set<String>,
        availableSideRegionIDs: [String]
    ) -> JourneyMapGuidance {
        let journey = journey(starterRegionID: starterRegionID)
        if let stop = journey.stops.first(where: { !completedStoryIDs.contains($0.chapter.storyID) }) {
            if stop.regionID == currentRegionID {
                return .continueStory(chapter: stop.chapter, objective: stop.objective)
            }
            return .travel(
                eyebrow: "主线下一站",
                title: stop.chapter.title,
                detail: stop.objective,
                regionIDs: [stop.regionID]
            )
        }

        let recommended = orderedUnique(
            journey.postStoryRegionIDs + availableSideRegionIDs
        )
        .filter { $0 != currentRegionID && !unlockedRegionIDs.contains($0) }

        if !recommended.isEmpty {
            return .travel(
                eyebrow: "主线之外",
                title: "把旅程写成自己的故事",
                detail: "五城主线已经完成，选择一座尚未到访的城市继续探索。",
                regionIDs: Array(recommended.prefix(4))
            )
        }

        let revisit = orderedUnique(journey.postStoryRegionIDs + availableSideRegionIDs)
            .filter { $0 != currentRegionID }
        if !revisit.isEmpty {
            return .travel(
                eyebrow: "自由旅行",
                title: "所有城市都已解锁",
                detail: "不再消耗机票，随时回到喜欢的城市继续活动。",
                regionIDs: Array(revisit.prefix(4))
            )
        }

        return .complete(
            title: "世界地图已经点亮",
            detail: "返回主线重温旅途，或等待下一段城市故事。"
        )
    }

    public static func unlockedMainCharacterRegionIDs(
        starterRegionID: String?,
        completedStoryIDs: Set<String>
    ) -> Set<String> {
        var regionIDs = Set([journey(starterRegionID: starterRegionID).starterRegionID])
        for chapter in [london, melbourne, newYork]
        where completedStoryIDs.contains(chapter.storyID) {
            regionIDs.insert(chapter.regionID)
        }
        return regionIDs
    }

    private static func journey(
        id: String,
        starterRegionID: String,
        title: String,
        characterOrder: [MainlineChapter],
        postStoryRegionIDs: [String]
    ) -> MainlineJourney {
        let objectives: [String] = [
            "与你选择的伙伴会合，找到声音地图的第一块线索。",
            "前往信号山追踪跨洋广播，确认这不是一场巧合。",
            "循着广播中的名字找到第二位伙伴，补上新的城市回声。",
            "找到最后一位伙伴，让三份线索指向同一个终点。",
            "带着完整线索抵达新加坡，揭开声音地图留下的真正邀请。",
        ]
        let chapters = [
            characterOrder[0],
            capeTown,
            characterOrder[1],
            characterOrder[2],
            singapore,
        ]
        return MainlineJourney(
            id: id,
            starterRegionID: starterRegionID,
            title: title,
            stops: zip(chapters, objectives).map(MainlineStop.init),
            postStoryRegionIDs: postStoryRegionIDs
        )
    }

    private static func orderedUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }
}

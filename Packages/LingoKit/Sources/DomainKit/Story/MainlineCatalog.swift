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

/// 一条主线中的城市章节。五站默认开放，序号由所选路线中的位置决定。
public struct MainlineStop: Sendable, Equatable, Hashable, Identifiable {
    public let chapter: MainlineChapter
    public let objective: String
    public let sequenceNumber: Int
    public let isFinale: Bool

    public var id: String { chapter.id }
    public var regionID: String { chapter.regionID }
    public var displayTitle: String {
        let heading = isFinale ? "终章" : "第\(Self.chineseNumber(sequenceNumber))章"
        return "\(heading) · \(chapter.title)"
    }

    public init(
        chapter: MainlineChapter,
        objective: String,
        sequenceNumber: Int,
        isFinale: Bool
    ) {
        self.chapter = chapter
        self.objective = objective
        self.sequenceNumber = sequenceNumber
        self.isFinale = isFinale
    }

    private static func chineseNumber(_ value: Int) -> String {
        switch value {
        case 1: "一"
        case 2: "二"
        case 3: "三"
        case 4: "四"
        default: String(value)
        }
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
        storyID: "departures_london_v1",
        regionID: "london",
        title: "空着的那把椅子",
        subtitle: "一页没念过的文字，以及一个由你陪伴的决定。"
    )
    public static let melbourne = MainlineChapter(
        storyID: "departures_mainline_melbourne_v1",
        regionID: "melbourne",
        title: "留给自己的一个下午",
        subtitle: "Ruby 已经答应了所有人，却还没答应自己。"
    )
    public static let newYork = MainlineChapter(
        storyID: "departures_mainline_newyork_v1",
        regionID: "newyork",
        title: "没有挂上的那张照片",
        subtitle: "Marcus 最满意的照片，遇到了一个明确的“不”。"
    )
    public static let capeTown = MainlineChapter(
        storyID: "departures_mainline_capetown_v1",
        regionID: "capetown",
        title: "故事是谁的",
        subtitle: "一场小型社区展览，不打算用一个声音代表所有人。"
    )
    public static let singapore = MainlineChapter(
        storyID: "departures_mainline_singapore_v1",
        regionID: "singapore",
        title: "下次见面的办法",
        subtitle: "旅程接近尾声，你想留下一个真正可以兑现的约定。"
    )

    public static let chapters: [MainlineChapter] = [
        london,
        melbourne,
        newYork,
        capeTown,
        singapore,
    ]

    /// 主线五城属于基础剧情内容，不需要机票即可前往。
    public static let defaultUnlockedRegionIDs = Set(chapters.map(\.regionID))

    public static let journeys: [MainlineJourney] = [
        journey(
            id: "departures-oliver",
            starterRegionID: "london",
            title: "从书店出发",
            characterOrder: [london, newYork, melbourne],
            postStoryRegionIDs: ["dublin", "edinburgh", "manchester", "toronto"]
        ),
        journey(
            id: "departures-ruby",
            starterRegionID: "melbourne",
            title: "从海边出发",
            characterOrder: [melbourne, london, newYork],
            postStoryRegionIDs: ["auckland", "sydney", "vancouver", "nairobi"]
        ),
        journey(
            id: "departures-marcus",
            starterRegionID: "newyork",
            title: "从街角出发",
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
                title: stop.displayTitle,
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
        where completedStoryIDs.contains(chapter.storyID) || completedStoryIDs.contains(DepartureStoryIdentity.rewardID(for: chapter.storyID) ?? chapter.storyID) {
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
        let chapters = [
            characterOrder[0],
            capeTown,
            characterOrder[1],
            characterOrder[2],
            singapore,
        ]
        let stops = chapters.enumerated().map { index, chapter in
            MainlineStop(
                chapter: chapter,
                objective: chapter.subtitle,
                sequenceNumber: index + 1,
                isFinale: index == chapters.count - 1
            )
        }
        return MainlineJourney(
            id: id,
            starterRegionID: starterRegionID,
            title: title,
            stops: stops,
            postStoryRegionIDs: postStoryRegionIDs
        )
    }

    private static func orderedUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }
}

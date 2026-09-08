import Testing
@testable import DomainKit

@Suite("MainlineCatalog")
struct MainlineCatalogTests {
    @Test("主线目录只包含五个主线章节")
    func mainlineChapterCatalog() {
        #expect(MainlineCatalog.chapters.count == 5)
        #expect(Set(MainlineCatalog.chapters.map(\.regionID)).count == 5)
        #expect(MainlineCatalog.chapters.allSatisfy { $0.storyID.hasPrefix("departures_") })
    }

    @Test("三条路线都经过五个主线城市，初始选择改变前期顺序")
    func routeShape() {
        #expect(MainlineCatalog.journeys.count == 3)
        for journey in MainlineCatalog.journeys {
            #expect(journey.stops.count == 5)
            #expect(Set(journey.stops.map(\.regionID)).count == 5)
            #expect(journey.stops.first?.regionID == journey.starterRegionID)
            #expect(journey.stops[1].regionID == "capetown")
            #expect(journey.stops.last?.regionID == "singapore")
        }

        let oliver = MainlineCatalog.journey(starterRegionID: "london")
        let ruby = MainlineCatalog.journey(starterRegionID: "melbourne")
        let marcus = MainlineCatalog.journey(starterRegionID: "newyork")
        #expect(oliver.stops.map(\.regionID) == [
            "london", "capetown", "newyork", "melbourne", "singapore",
        ])
        #expect(ruby.stops.map(\.regionID) == [
            "melbourne", "capetown", "london", "newyork", "singapore",
        ])
        #expect(marcus.stops.map(\.regionID) == [
            "newyork", "capetown", "melbourne", "london", "singapore",
        ])

        for journey in MainlineCatalog.journeys {
            #expect(journey.stops.map(\.displayTitle).count == 5)
            #expect(Set(journey.stops.map(\.displayTitle)).count == 5)
            #expect(journey.stops[0].displayTitle.hasPrefix("第一章 ·"))
            #expect(journey.stops[1].displayTitle.hasPrefix("第二章 ·"))
            #expect(journey.stops[2].displayTitle.hasPrefix("第三章 ·"))
            #expect(journey.stops[3].displayTitle.hasPrefix("第四章 ·"))
            #expect(journey.stops[4].displayTitle.hasPrefix("终章 ·"))
        }
    }

    @Test("地图引导不会把当前城市当成下一站")
    func currentCityBecomesStoryPrompt() {
        let guidance = MainlineCatalog.mapGuidance(
            starterRegionID: "london",
            currentRegionID: "london",
            completedStoryIDs: [],
            unlockedRegionIDs: ["london"],
            availableSideRegionIDs: []
        )
        guard case .continueStory(let chapter, _) = guidance else {
            Issue.record("当前主线城市应显示继续剧情")
            return
        }
        #expect(chapter.regionID == "london")
    }

    @Test("完成当前站后只推荐配置中的下一站")
    func nextRequiredCity() {
        let guidance = MainlineCatalog.mapGuidance(
            starterRegionID: "london",
            currentRegionID: "london",
            completedStoryIDs: [MainlineCatalog.london.storyID],
            unlockedRegionIDs: ["london"],
            availableSideRegionIDs: ["dublin", "toronto"]
        )
        guard case .travel(_, _, _, let regionIDs) = guidance else {
            Issue.record("应引导前往下一座主线城市")
            return
        }
        #expect(regionIDs == ["capetown"])
    }

    @Test("主线完成后按配置给出多个支线目的地，并过滤当前与已解锁城市")
    func postStorySuggestions() {
        let journey = MainlineCatalog.journey(starterRegionID: "london")
        let completed = Set(journey.stops.map(\.chapter.storyID))
        let guidance = MainlineCatalog.mapGuidance(
            starterRegionID: "london",
            currentRegionID: "dublin",
            completedStoryIDs: completed,
            unlockedRegionIDs: ["dublin", "edinburgh"],
            availableSideRegionIDs: [
                "dublin", "edinburgh", "manchester", "toronto", "sydney",
            ]
        )
        guard case .travel(_, _, _, let regionIDs) = guidance else {
            Issue.record("应推荐未解锁支线城市")
            return
        }
        #expect(!regionIDs.contains("dublin"))
        #expect(!regionIDs.contains("edinburgh"))
        #expect(regionIDs.count >= 2)
    }

    @Test("伙伴解锁顺序由初始路线与已完成相遇剧情共同决定")
    func characterUnlocks() {
        #expect(
            MainlineCatalog.unlockedMainCharacterRegionIDs(
                starterRegionID: "melbourne",
                completedStoryIDs: []
            ) == ["melbourne"]
        )
        #expect(
            MainlineCatalog.unlockedMainCharacterRegionIDs(
                starterRegionID: "melbourne",
                completedStoryIDs: ["mainline_london"]
            ) == ["melbourne", "london"]
        )
    }
}

@Suite("CityStoryCatalog")
struct CityStoryCatalogTests {
    @Test("十五座城市各有且仅有一篇城市剧情")
    func everyCityHasOneStory() {
        let chapters = CityStoryCatalog.chapters
        #expect(chapters.count == 15)
        #expect(Set(chapters.map(\.storyID)).count == 15)
        #expect(Set(chapters.map(\.regionID)) == [
            "london", "melbourne", "newyork", "capetown", "singapore",
            "dublin", "edinburgh", "vancouver", "auckland", "nairobi",
            "toronto", "sydney", "neworleans", "manchester", "kingston",
        ])
    }

    @Test("可按城市查找对应剧情")
    func lookupByRegion() {
        #expect(CityStoryCatalog.chapter(forRegion: "kingston")?.title == "节目末尾的名字")
        #expect(CityStoryCatalog.chapter(forRegion: "unknown") == nil)
    }

    @Test("前六篇默认开放，之后每张机票开放三篇")
    func ticketUnlockMilestones() {
        #expect(CityStoryCatalog.unlockedChapterCount(earnedTicketCount: 0) == 6)
        #expect(CityStoryCatalog.unlockedChapterCount(earnedTicketCount: 1) == 9)
        #expect(CityStoryCatalog.unlockedChapterCount(earnedTicketCount: 2) == 12)
        #expect(CityStoryCatalog.unlockedChapterCount(earnedTicketCount: 3) == 15)
        #expect(CityStoryCatalog.unlockedChapterCount(earnedTicketCount: 99) == 15)

        #expect(CityStoryCatalog.requiredTicketCount(forChapterAt: 5) == 0)
        #expect(CityStoryCatalog.requiredTicketCount(forChapterAt: 6) == 1)
        #expect(CityStoryCatalog.requiredTicketCount(forChapterAt: 8) == 1)
        #expect(CityStoryCatalog.requiredTicketCount(forChapterAt: 9) == 2)
        #expect(CityStoryCatalog.requiredTicketCount(forChapterAt: 12) == 3)
    }
}

import DomainKit
import Foundation
import Testing
import UIKit
@testable import PersistenceKit

/// 校验随包种子数据的完整性与一致性。
@Suite("种子数据")
struct SeedDataTests {
    @Test("音色属性保存，旧人物卡无音色时稳定恢复")
    func readingVoicePersistence() throws {
        let url = try #require(Bundle.main.url(forResource: "main_characters", withExtension: "json"))
        let cards = try SeedData.mainCharacterCards(url: url)
        for card in cards {
            var old = card
            old.readingVoice = nil
            let raw = try JSONEncoder().encode(old)
            let decoded = try JSONDecoder().decode(CharacterCard.self, from: raw)
            #expect(decoded.resolvedReadingVoice == card.resolvedReadingVoice)
            let stored = try #require(CharacterCard.decode(fromJSON: decoded.encodedJSON()))
            #expect(stored.readingVoice == card.resolvedReadingVoice)
        }
        var custom = cards[1]
        custom.readingVoice = .f2
        #expect(CharacterCard.decode(fromJSON: custom.encodedJSON())?.readingVoice == .f2)
        custom.nationality = "British"
        #expect(custom.resolvedReadingVoice == .f5)
    }

    @Test("main_characters.json：3 位主角色，地区各不相同且都在 regions.json 中")
    func mainCharacters() throws {
        let cardsURL = try #require(Bundle.main.url(forResource: "main_characters", withExtension: "json"))
        let cards = try SeedData.mainCharacterCards(url: cardsURL)
        #expect(cards.count == 3)
        #expect(cards.map(\.readingVoice) == [.m5, .f3, .m3])

        let regionsURL = try #require(Bundle.main.url(forResource: "regions", withExtension: "json"))
        let catalog = try RegionCatalog(url: regionsURL)
        let regionIDs = cards.map(\.regionID)
        #expect(Set(regionIDs).count == 3)
        for id in regionIDs {
            #expect(catalog.region(id: id) != nil, "未知地区: \(id)")
        }
        for card in cards {
            #expect(!card.personality.isEmpty)
            #expect(!card.appearance.isEmpty)
            #expect(card.speechStyle?.isEmpty == false)
            #expect(card.background?.isEmpty == false)
            #expect(!card.hobbies.isEmpty)
            #expect(card.activityProfile != nil)
            #expect(TimeZone(identifier: card.activityProfile?.timeZoneIdentifier ?? "") != nil)
            #expect((4...12).contains(card.activityProfile?.focusDurationMinutes ?? 0))
        }
    }

    @Test("regions.json：15 座城市均服务于英语学习")
    func regions() throws {
        let regionsURL = try #require(Bundle.main.url(forResource: "regions", withExtension: "json"))
        let catalog = try RegionCatalog(url: regionsURL)
        #expect(catalog.regions.count == 15)
        #expect(catalog.mainlineRegions.count == 5)
        #expect(catalog.sideRegions.count == 10)
        #expect(Set(catalog.mainlineRegions.map(\.id)) == [
            "london", "melbourne", "newyork", "capetown", "singapore",
        ])
        #expect(Set(catalog.regions.map(\.id)) == [
            "london", "melbourne", "newyork", "capetown", "singapore",
            "dublin", "edinburgh", "vancouver", "auckland", "nairobi",
            "toronto", "sydney", "neworleans", "manchester", "kingston",
        ])
        #expect(
            catalog.regions.allSatisfy {
                $0.learningLanguageCode == RegionCatalog.supportedLearningLanguageCode
            }
        )
        for region in catalog.regions {
            #expect(region.activities.count == 5, "\(region.nameZh) 应配置 5 条活动路线")
            #expect(Set(region.activities.map(\.id)).count == region.activities.count)
            #expect(!region.landmarks.isEmpty)
            for activity in region.activities {
                #expect(activity.durationMinutes >= 20)
                #expect((0.25...0.6).contains(activity.encounterProbability))
                #expect(!activity.outcomeZh.isEmpty)
            }
        }
        #expect(
            Set(catalog.regions.flatMap(\.activities).map(\.category))
                == Set(Region.ActivityCategory.allCases)
        )
    }

    @Test("目录层隐藏非当前学习语言城市")
    func unsupportedLearningLanguageIsHidden() {
        let englishRegion = Region(
            id: "london",
            nameEn: "London",
            nameZh: "伦敦",
            countryCode: "GB",
            countryNameEn: "United Kingdom",
            countryNameZh: "英国",
            learningLanguageCode: "en",
            taglineZh: "-",
            landmarks: [],
            activities: []
        )
        let japaneseRegion = Region(
            id: "tokyo",
            nameEn: "Tokyo",
            nameZh: "东京",
            countryCode: "JP",
            countryNameEn: "Japan",
            countryNameZh: "日本",
            learningLanguageCode: "ja",
            taglineZh: "-",
            landmarks: [],
            activities: []
        )

        let catalog = RegionCatalog(regions: [englishRegion, japaneseRegion])

        #expect(catalog.regions.map(\.id) == ["london"])
        #expect(catalog.region(id: "tokyo") == nil)
    }

    @Test("城市：每座城市都有背景、主线与活动美术")
    func homeArtworkCoverage() throws {
        let regionsURL = try #require(
            Bundle.main.url(forResource: "regions", withExtension: "json")
        )
        let catalog = try RegionCatalog(url: regionsURL)

        for region in catalog.regions {
            for prefix in ["city_backdrop", "home_mainline", "home_activity"] {
                let assetName = "\(prefix)_\(region.id)"
                #expect(
                    UIImage(
                        named: assetName,
                        in: Bundle.main,
                        compatibleWith: nil
                    ) != nil,
                    "缺少城市美术：\(assetName)"
                )
            }
        }
    }
}

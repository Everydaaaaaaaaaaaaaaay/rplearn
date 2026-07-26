import DomainKit
import Foundation
import Testing
import UIKit
@testable import PersistenceKit

/// 校验随包种子数据的完整性与一致性。
@Suite("种子数据")
struct SeedDataTests {
    @Test("main_characters.json：3 位主角色，地区各不相同且都在 regions.json 中")
    func mainCharacters() throws {
        let cardsURL = try #require(Bundle.main.url(forResource: "main_characters", withExtension: "json"))
        let cards = try SeedData.mainCharacterCards(url: cardsURL)
        #expect(cards.count == 3)

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
        }
    }

    @Test("regions.json：5 个主线城市、8 个支线城市且不含中国城市")
    func regions() throws {
        let regionsURL = try #require(Bundle.main.url(forResource: "regions", withExtension: "json"))
        let catalog = try RegionCatalog(url: regionsURL)
        #expect(catalog.regions.count == 13)
        #expect(catalog.mainlineRegions.count == 5)
        #expect(catalog.sideRegions.count == 8)
        #expect(Set(catalog.mainlineRegions.map(\.id)) == [
            "london", "melbourne", "newyork", "capetown", "singapore",
        ])
        #expect(!catalog.regions.contains { $0.countryCode == "CN" })
        for region in catalog.regions {
            #expect(!region.activities.isEmpty)
            #expect(!region.landmarks.isEmpty)
        }
    }

    @Test("首页：每座城市都有背景、主线与活动美术")
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

import DomainKit
import Foundation
import Testing
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

    @Test("regions.json：初始三地区齐全且都有活动")
    func regions() throws {
        let regionsURL = try #require(Bundle.main.url(forResource: "regions", withExtension: "json"))
        let catalog = try RegionCatalog(url: regionsURL)
        #expect(Set(catalog.regions.map(\.id)) == ["london", "melbourne", "newyork"])
        for region in catalog.regions {
            #expect(!region.activities.isEmpty)
            #expect(!region.landmarks.isEmpty)
        }
    }
}

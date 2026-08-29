import Foundation
import PersistenceKit
import Testing
@testable import RosterFeature

@Suite("RosterPresentationPolicy")
struct RosterPresentationPolicyTests {
    @Test("联系人按姓名排序，特别关心只在非搜索状态出现")
    func orderingAndFavoriteVisibility() {
        let contacts = [
            character(name: "Zoe", isFavorite: true),
            character(name: "Amy"),
            character(name: "Ben", isFavorite: true),
        ]

        #expect(RosterPresentationPolicy.sorted(contacts).map(\.card.name) == ["Amy", "Ben", "Zoe"])
        #expect(
            RosterPresentationPolicy.favoriteContacts(in: contacts, isSearching: false)
                .map(\.card.name) == ["Ben", "Zoe"]
        )
        #expect(
            RosterPresentationPolicy.friendGroupContacts(in: contacts)
                .map(\.card.name) == ["Amy"]
        )
        #expect(
            RosterPresentationPolicy.favoriteContacts(in: contacts, isSearching: true).isEmpty
        )
        #expect(
            RosterPresentationPolicy.favoriteContacts(
                in: [character(name: "Amy")],
                isSearching: false
            ).isEmpty
        )
        #expect(
            RosterPresentationPolicy.favoriteContacts(
                in: [character(name: "Amy", isFavorite: true)],
                isSearching: false
            ).map(\.card.name) == ["Amy"]
        )
    }

    @Test("搜索姓名、职业、国籍、地区并忽略首尾空白")
    func searchFields() {
        let contacts = [
            character(name: "Oliver", nationality: "英国", occupation: "二手书店店员"),
            character(
                name: "Ruby",
                nationality: "澳大利亚",
                occupation: "冲浪教练",
                regionID: "melbourne"
            ),
        ]
        let regionName: (String) -> String = { $0 == "melbourne" ? "墨尔本" : "伦敦" }

        #expect(
            RosterPresentationPolicy.filtered(contacts, query: " 书店 ", regionName: regionName)
                .map(\.card.name) == ["Oliver"]
        )
        #expect(
            RosterPresentationPolicy.filtered(contacts, query: "墨尔本", regionName: regionName)
                .map(\.card.name) == ["Ruby"]
        )
        #expect(
            RosterPresentationPolicy.filtered(contacts, query: "澳大利亚", regionName: regionName)
                .map(\.card.name) == ["Ruby"]
        )
        #expect(
            RosterPresentationPolicy.filtered(contacts, query: "不存在", regionName: regionName)
                .isEmpty
        )
    }

    @Test("好友位达到八成时提升提示等级")
    func capacityThreshold() {
        #expect(!RosterPresentationPolicy.isCapacityNearLimit(occupied: 23, limit: 30))
        #expect(RosterPresentationPolicy.isCapacityNearLimit(occupied: 24, limit: 30))
        #expect(RosterPresentationPolicy.isCapacityNearLimit(occupied: 30, limit: 30))
        #expect(RosterPresentationPolicy.isCapacityNearLimit(occupied: 0, limit: 0))
    }

    private func character(
        name: String,
        nationality: String = "英国",
        occupation: String = "摄影师",
        regionID: String = "london",
        isFavorite: Bool = false
    ) -> CharacterDTO {
        CharacterDTO(
            id: UUID(),
            card: CharacterCard(
                name: name,
                age: 24,
                gender: .other,
                nationality: nationality,
                regionID: regionID,
                occupation: occupation,
                hobbies: [],
                appearance: "",
                personality: ""
            ),
            difficultyLevel: .junior3,
            isMainCharacter: false,
            isFriend: true,
            metAt: .now,
            isFavorite: isFavorite
        )
    }
}

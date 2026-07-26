import Testing
@testable import PersistenceKit

@Suite("角色爱好标签本地化")
struct CharacterHobbyLocalizationTests {
    @Test("兼容旧版已保存的英文偶遇标签")
    func localizesLegacyEncounterHobbies() {
        let card = makeCard(
            hobbies: [
                "making handmade pasta",
                "collecting vinyl records",
                "playing table tennis",
            ]
        )

        #expect(card.localizedHobbies == ["做手工意面", "收藏黑胶唱片", "打乒乓球"])
    }

    @Test("已经本地化的标签保持原样")
    func preservesLocalizedHobbies() {
        let card = makeCard(hobbies: ["冲浪", "露营和观星"])
        #expect(card.localizedHobbies == ["冲浪", "露营和观星"])
    }

    @Test("英文匹配忽略大小写和首尾空白")
    func normalizesLegacyKeys() {
        let card = makeCard(hobbies: ["  Film Photography ", "YOGA"])
        #expect(card.localizedHobbies == ["胶片摄影", "瑜伽"])
    }

    private func makeCard(hobbies: [String]) -> CharacterCard {
        CharacterCard(
            name: "Poppy",
            age: 27,
            gender: .female,
            nationality: "British",
            regionID: "london",
            occupation: "florist",
            hobbies: hobbies,
            appearance: "red coat",
            personality: "warm"
        )
    }
}

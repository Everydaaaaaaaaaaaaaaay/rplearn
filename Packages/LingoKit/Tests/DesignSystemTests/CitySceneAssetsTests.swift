import DesignSystem
import Testing

@Suite("城市摄影资源映射")
struct CitySceneAssetsTests {
    @Test("十五座城市分别生成信息、联系人与学习页资源名")
    func supportedCitiesGenerateBothSceneNames() {
        #expect(DSCitySceneAssets.supportedRegionIDs.count == 15)

        for regionID in DSCitySceneAssets.supportedRegionIDs {
            #expect(
                DSCitySceneAssets.imageName(for: .messages, regionID: regionID)
                    == "messages_\(regionID)_glass"
            )
            #expect(
                DSCitySceneAssets.imageName(for: .contacts, regionID: regionID)
                    == "contacts_\(regionID)_glass"
            )
            #expect(
                DSCitySceneAssets.imageName(for: .learning, regionID: regionID)
                    == "learning_\(regionID)_glass"
            )
        }
    }

    @Test("空值和未知地区回退到伦敦")
    func unsupportedRegionFallsBackToLondon() {
        #expect(
            DSCitySceneAssets.imageName(for: .messages, regionID: nil)
                == "messages_london_glass"
        )
        #expect(
            DSCitySceneAssets.imageName(for: .contacts, regionID: "  future-city  ")
                == "contacts_london_glass"
        )
        #expect(DSCitySceneAssets.imageName(for: .learning, regionID: nil) == "learning_london_glass")
        #expect(DSCitySceneAssets.imageName(for: .learning, regionID: "future-city") == "learning_london_glass")
    }

    @Test("地区标识允许大小写和首尾空格")
    func regionIDIsNormalized() {
        #expect(
            DSCitySceneAssets.imageName(for: .messages, regionID: "  Sydney ")
                == "messages_sydney_glass"
        )
        #expect(DSCitySceneAssets.imageName(for: .learning, regionID: "  Sydney ") == "learning_sydney_glass")
    }
}

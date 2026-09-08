@testable import DesignSystem
import Testing

struct BrandMascotRenderingPolicyTests {
    @Test("全部品牌姿态只映射到新版动作资源")
    func poseAssetMapping() {
        let names = Set(BrandMascotPose.allCases.map(\.assetName))

        #expect(names.count == 8)
        #expect(names == [
            "mascot_gugu_welcome",
            "mascot_gugu_celebrate",
            "mascot_gugu_explore",
            "mascot_gugu_rest",
            "mascot_gaga_pout",
            "mascot_gaga_proud",
            "mascot_gaga_care",
            "mascot_gaga_think",
        ])
        #expect(names.allSatisfy { $0.hasPrefix("mascot_") })
    }

    @Test("双吉祥物姿态使用正确角色名")
    func poseCharacterMapping() {
        #expect(BrandMascotPose.greeting.characterName == "咕咕")
        #expect(BrandMascotPose.guide.characterName == "咕咕")
        #expect(BrandMascotPose.celebrate.characterName == "咕咕")
        #expect(BrandMascotPose.resting.characterName == "咕咕")
        #expect(BrandMascotPose.coach.characterName == "嘎嘎")
        #expect(BrandMascotPose.reminder.characterName == "嘎嘎")
        #expect(BrandMascotPose.encouragement.characterName == "嘎嘎")
        #expect(BrandMascotPose.achievement.characterName == "嘎嘎")
    }
}

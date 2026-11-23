@testable import DesignSystem
import Foundation
import Testing

struct BrandMascotRenderingPolicyTests {
    @Test("品牌姿态映射到咕咕与嘎嘎，八种姿态各不相同")
    func posePuffMapping() {
        #expect(Set(BrandMascotPose.allCases.map { "\($0.puffBird)-\($0.puffPose)" }).count == 8)
        for pose in BrandMascotPose.allCases {
            #expect(pose.puffBird.name == pose.characterName)
        }
        #expect(BrandMascotPose.greeting.puffPose == .wave)
        #expect(BrandMascotPose.resting.puffPose == .sleepy)
        #expect(BrandMascotPose.coach.puffPose == .thinking)
    }

    @Test("八种品牌姿态逐一显示改版前 2D 动作资源包里的八张图")
    func brandPosesUseOriginalArt() {
        let art = Dictionary(uniqueKeysWithValues: BrandMascotPose.allCases.map {
            ($0, PuffMascot.artName($0.puffBird, $0.puffPose))
        })
        #expect(art[.greeting] == "mascot_gugu_welcome")
        #expect(art[.guide] == "mascot_gugu_explore")
        #expect(art[.celebrate] == "mascot_gugu_celebrate")
        #expect(art[.resting] == "mascot_gugu_rest")
        #expect(art[.coach] == "mascot_gaga_think")
        #expect(art[.reminder] == "mascot_gaga_pout")
        #expect(art[.encouragement] == "mascot_gaga_care")
        #expect(art[.achievement] == "mascot_gaga_proud")
        for pose in PuffMascot.Pose.allCases {
            #expect(PuffMascot.artName(.gugu, pose).hasPrefix("mascot_gugu_"))
            #expect(PuffMascot.artName(.gaga, pose).hasPrefix("mascot_gaga_"))
        }
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

    @Test("建议角色按消息稳定分桶且两位吉祥物都可出现")
    func coachPersonaAssignment() throws {
        let even = try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000000"))
        let odd = try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000001"))

        #expect(DSCoachPersona.assigned(to: even) == .gugu)
        #expect(DSCoachPersona.assigned(to: odd) == .gaga)
        #expect(DSCoachPersona.assigned(to: even).title == "咕咕建议")
        #expect(DSCoachPersona.assigned(to: odd).title == "嘎嘎建议")
        #expect(DSCoachPersona.assigned(to: even).pose == .guide)
        #expect(DSCoachPersona.assigned(to: odd).pose == .coach)
    }
}

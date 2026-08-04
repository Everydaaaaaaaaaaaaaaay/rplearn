import DesignSystem
import MascotKit
import Testing

struct BrandMascotRenderingPolicyTests {
    @Test("自动策略只在可读尺寸启用动画模型")
    func automaticRenderingThreshold() {
        #expect(!BrandMascotRenderingMode.automatic.usesAnimatedModel(at: 51))
        #expect(BrandMascotRenderingMode.automatic.usesAnimatedModel(at: 52))
        #expect(BrandMascotRenderingMode.animatedModel.usesAnimatedModel(at: 28))
        #expect(!BrandMascotRenderingMode.staticArtwork.usesAnimatedModel(at: 92))
    }

    @Test("品牌姿态映射到稳定动画语义")
    func poseAnimationMapping() {
        #expect(BrandMascotPose.greeting.defaultAnimation == .semantic(.idle))
        #expect(BrandMascotPose.guide.defaultAnimation == .semantic(.idle))
        #expect(BrandMascotPose.coach.defaultAnimation == .semantic(.idle))
        #expect(BrandMascotPose.celebrate.defaultAnimation == .semantic(.success))
    }
}

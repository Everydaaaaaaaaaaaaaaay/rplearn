import SwiftUI
import Testing
@testable import DesignSystem

@Suite("场景拖动阻尼")
struct SceneDragMotionTests {
    @Test("静止不改变原构图")
    func restingPose() {
        let pose = DSSceneDragPose.resolve(translation: .zero, viewport: CGSize(width: 402, height: 874))
        #expect(pose.offset == .zero)
        #expect(pose.scale == 1)
        #expect(pose.pitch == 0 && pose.yaw == 0)
    }

    @Test("任意方向的大幅拖动都受约束", arguments: [CGSize(width: 320, height: 568), CGSize(width: 874, height: 402)])
    func boundedMotion(viewport: CGSize) {
        for translation in [CGSize(width: 10_000, height: 10_000), CGSize(width: -10_000, height: 300), CGSize(width: 0, height: -10_000)] {
            let pose = DSSceneDragPose.resolve(translation: translation, viewport: viewport)
            #expect(hypot(pose.offset.width, pose.offset.height) < 8)
            #expect(abs(pose.pitch) <= 0.5 && abs(pose.yaw) <= 0.5)
            #expect((pose.scale - 1) * viewport.width / 2 > abs(pose.offset.width))
            #expect((pose.scale - 1) * viewport.height / 2 > abs(pose.offset.height))
        }
    }

    @Test("相同拖动增量产生递减位移")
    func progressiveResistance() {
        let offsets = [0, 50, 100, 150].map {
            DSSceneDragPose.resolve(translation: CGSize(width: 0, height: $0), viewport: CGSize(width: 402, height: 874)).offset.height
        }
        #expect(offsets[1] > offsets[0])
        #expect(offsets[2] - offsets[1] < offsets[1] - offsets[0])
        #expect(offsets[3] - offsets[2] < offsets[2] - offsets[1])
    }
}

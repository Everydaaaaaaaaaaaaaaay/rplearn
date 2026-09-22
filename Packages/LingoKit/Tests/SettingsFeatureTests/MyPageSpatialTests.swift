import SwiftUI
import Testing
@testable import SettingsFeature

@Suite("我的页空间拖动")
struct MyPageSpatialTests {
    @Test("静止还原、阻力递增且重新抓取可逆")
    func resistance() {
        #expect(MyPageSpatialGeometry.resisted(.zero) == .zero)
        #expect(MyPageSpatialGeometry.coverageScale(camera: .zero) == 1)
        var previous: CGFloat = 0
        var previousIncrement = CGFloat.infinity
        for x in stride(from: 20, through: 400, by: 20) {
            let input = CGSize(width: x, height: x / 2)
            let result = MyPageSpatialGeometry.resisted(input)
            #expect(hypot(result.width, result.height) < MyPageSpatialGeometry.cameraLimit)
            let increment = result.width - previous
            #expect(increment > 0 && increment < previousIncrement)
            let restored = MyPageSpatialGeometry.unresisted(result)
            #expect(abs(restored.width - input.width) < 0.0001)
            #expect(abs(restored.height - input.height) < 0.0001)
            previous = result.width
            previousIncrement = increment
        }
    }

    @Test("最大视点下网格不折叠且边缘覆盖足够")
    func geometry() {
        let size = MyPageSpatialGeometry.size
        for camera in [CGSize(width: 34, height: 0), CGSize(width: -24, height: 24), CGSize(width: 0, height: -34)] {
            func project(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                let d = MyPageSpatialGeometry.depth(at: CGPoint(x: x / size.width, y: y / size.height))
                return CGPoint(x: x + camera.width * d, y: y + camera.height * d)
            }
            for y in stride(from: CGFloat(0), to: size.height - 4, by: 4) {
                for x in stride(from: CGFloat(0), to: size.width - 4, by: 4) {
                    let a = project(x, y), b = project(x + 4, y), c = project(x, y + 4)
                    #expect((b.x-a.x) * (c.y-a.y) - (b.y-a.y) * (c.x-a.x) > 0)
                }
            }
            let scale = MyPageSpatialGeometry.coverageScale(camera: camera)
            #expect((scale - 1) * size.width / 2 >= abs(camera.width) * 0.11 - 0.0001)
            #expect((scale - 1) * size.height / 2 >= abs(camera.height) * 0.11 - 0.0001)
        }
        #expect(MyPageSpatialGeometry.depth(at: CGPoint(x: 441.0 / 825, y: 424.0 / 1906)) >
                MyPageSpatialGeometry.depth(at: CGPoint(x: 0.5, y: 0.05)) + 0.25)
    }

    @Test("回弹能被原地抓住、无输入延迟且最终停止")
    @MainActor
    func interruption() {
        let motion = MyPageSpatialMotion()
        motion.drag(CGSize(width: 120, height: -40), time: 1)
        #expect(motion.camera == MyPageSpatialGeometry.resisted(CGSize(width: 120, height: -40)))
        motion.release(time: 1.2)
        motion.advance(seconds: 0.08)
        let before = motion.camera
        motion.drag(.zero, time: 1.3)
        #expect(abs(motion.camera.width - before.width) < 0.0001)
        #expect(abs(motion.camera.height - before.height) < 0.0001)
        motion.release(time: 1.4)
        for _ in 0..<180 { motion.advance(seconds: 1.0 / 120) }
        #expect(motion.camera == .zero)
        motion.reset()
    }
}

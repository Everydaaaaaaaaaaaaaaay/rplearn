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

    @Test("物件轮廓刚性平移、最大露出带在微补全范围内")
    func geometry() {
        for layer in MyPageSpatialGeometry.layers {
            #expect(layer.contour.count >= 3)
            #expect(layer.bounds.width > 0 && layer.bounds.height > 0)
            let camera = CGSize(width: -24, height: 24)
            let offset = layer.offset(camera: camera)
            let original = layer.contour
            let moved = original.map { CGPoint(x: $0.x * 402 + offset.width, y: $0.y * MyPageSpatialGeometry.size.height + offset.height) }
            for i in 1..<original.count {
                let before = hypot((original[i].x-original[i-1].x)*402,
                                   (original[i].y-original[i-1].y)*MyPageSpatialGeometry.size.height)
                let after = hypot(moved[i].x-moved[i-1].x, moved[i].y-moved[i-1].y)
                #expect(abs(before - after) < 0.0001)
            }
            let exposedPixels = abs(layer.depth - MyPageSpatialGeometry.backgroundDepth) * 34 * 825 / 320
            #expect(exposedPixels + 10 < 48)
        }
        #expect(MyPageSpatialGeometry.depth(at: CGPoint(x: 441.0 / 825, y: 424.0 / 1906)) >
                MyPageSpatialGeometry.depth(at: CGPoint(x: 0.5, y: 0.05)) + 0.15)
    }

    @Test("八件物品及细小附件只属于自身图层")
    func objectOwnership() {
        let anchors: [(Int, CGPoint)] = [
            (0, CGPoint(x: 280, y: 375)), (1, CGPoint(x: 440, y: 424)),
            (2, CGPoint(x: 700, y: 355)), (2, CGPoint(x: 791, y: 472)),
            (3, CGPoint(x: 410, y: 930)), (4, CGPoint(x: 170, y: 1450)),
            (4, CGPoint(x: 109, y: 1680)), (5, CGPoint(x: 420, y: 1500)),
            (6, CGPoint(x: 620, y: 1500)), (6, CGPoint(x: 660, y: 1310)),
            (6, CGPoint(x: 549, y: 1740)), (7, CGPoint(x: 720, y: 1550)),
        ]
        for (expected, pixel) in anchors {
            let point = CGPoint(x: pixel.x / 825, y: pixel.y / 1906)
            let owners = MyPageSpatialGeometry.layers.indices.filter { MyPageSpatialGeometry.layers[$0].contains(point) }
            #expect(owners == [expected], "物件或附件误入相邻图层")
        }
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

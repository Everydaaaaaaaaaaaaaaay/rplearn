import SwiftUI
import Testing
@testable import HomeFeature

@Suite("活动首页空间视点")
struct HomeSpatialGeometryTests {
    @Test("十五城都有深度标定，远景比墙面移动少")
    func calibratedCities() {
        #expect((HomeSpatialGeometry.foregroundDepth - HomeSpatialGeometry.backgroundDepth) * 34 * 853 / 320 + 2 < 48)
        #expect(Set(HomeDepartureSceneLayout.scenes.keys) == Set(HomeSpatialGeometry.calibrations.keys))
        let london = HomeSpatialGeometry(assetName: "home_city_london")
        #expect(london.depth(at: CGPoint(x: 0.435, y: 0.475)) == HomeSpatialGeometry.foregroundDepth)
        #expect(london.depth(at: CGPoint(x: 0.17, y: 0.58)) == HomeSpatialGeometry.backgroundDepth)
        for layout in HomeDepartureSceneLayout.scenes.values {
            let geometry = HomeSpatialGeometry(assetName: layout.assetName)
            let center = CGPoint(x: geometry.opening.midX, y: geometry.opening.midY)
            #expect(geometry.depth(at: center) < 0.04)
            #expect(geometry.depth(at: CGPoint(x: 0.9, y: 0.4)) > 0.15)
            #expect(geometry.depth(at: CGPoint(x: 0.9, y: 0.98)) == HomeSpatialGeometry.foregroundDepth)
            #expect(geometry.project(center, camera: .zero, size: CGSize(width: 402, height: 874)) == center)
        }
    }

    @Test("逐城语义锚点：门外盆栽和门廊归远景，门把手与窗棂归室内")
    func semanticOwnership() {
        // 独立对照原图选择物体内部点，不能从待测轮廓反推期望值。
        let probes: [(String, CGPoint, CGPoint)] = [
            ("auckland", CGPoint(x: 180, y: 965), CGPoint(x: 360, y: 837)),
            ("capetown", CGPoint(x: 118, y: 969), CGPoint(x: 361, y: 867)),
            ("dublin", CGPoint(x: 145, y: 324), CGPoint(x: 334, y: 824)),
            ("edinburgh", CGPoint(x: 220, y: 1100), CGPoint(x: 370, y: 820)),
            ("kingston", CGPoint(x: 111, y: 990), CGPoint(x: 345, y: 824)),
            ("london", CGPoint(x: 150, y: 1070), CGPoint(x: 374, y: 877)),
            ("manchester", CGPoint(x: 145, y: 810), CGPoint(x: 360, y: 855)),
            ("melbourne", CGPoint(x: 130, y: 890), CGPoint(x: 90, y: 805)),
            ("nairobi", CGPoint(x: 230, y: 407), CGPoint(x: 360, y: 798)),
            ("neworleans", CGPoint(x: 145, y: 966), CGPoint(x: 346, y: 919)),
            ("newyork", CGPoint(x: 210, y: 355), CGPoint(x: 342, y: 817)),
            ("singapore", CGPoint(x: 233, y: 367), CGPoint(x: 361, y: 836)),
            ("sydney", CGPoint(x: 132, y: 1000), CGPoint(x: 122, y: 886)),
            ("toronto", CGPoint(x: 215, y: 401), CGPoint(x: 94, y: 828)),
            ("vancouver", CGPoint(x: 119, y: 1040), CGPoint(x: 359, y: 900)),
        ]
        for (city, outdoors, foreground) in probes {
            let geometry = HomeSpatialGeometry(assetName: "home_city_" + city)
            let size = HomeSpatialGeometry.calibrations[city]!.sourceSize
            func normalized(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x / size.width, y: point.y / size.height) }
            #expect(geometry.depth(at: normalized(outdoors)) == HomeSpatialGeometry.backgroundDepth, "门外物体误入室内层：\(city)")
            #expect(geometry.depth(at: normalized(foreground)) == HomeSpatialGeometry.foregroundDepth, "门把手误入远景：\(city)")
        }
        let dublin = HomeSpatialGeometry(assetName: "home_city_dublin")
        #expect(dublin.layers[0].contours.count == 8)
        #expect(dublin.depth(at: CGPoint(x: 220.0 / 850, y: 320.0 / 1838)) == HomeSpatialGeometry.foregroundDepth)
        #expect(dublin.depth(at: CGPoint(x: 220.0 / 850, y: 387.0 / 1838)) == HomeSpatialGeometry.backgroundDepth)
        let london = HomeSpatialGeometry(assetName: "home_city_london")
        #expect(london.depth(at: CGPoint(x: 118.0 / 853, y: 1124.0 / 1844)) == HomeSpatialGeometry.foregroundDepth)
        #expect(london.depth(at: CGPoint(x: 150.0 / 853, y: 1000.0 / 1844)) == HomeSpatialGeometry.backgroundDepth)
    }

    @Test("刚性室内前景在标准与短屏保持形状、无露底")
    func boundedProjection() {
        for viewport in [CGSize(width: 402, height: 874), CGSize(width: 320, height: 568)] {
            let placement = HomeDepartureCanvas.placement(in: viewport)
            let size = CGSize(width: 402, height: placement.height)
            for layout in HomeDepartureSceneLayout.scenes.values {
                let geometry = HomeSpatialGeometry(assetName: layout.assetName)
                for camera in [CGSize(width: 24, height: 24), CGSize(width: -24, height: -24)] {
                    let scale = HomeSpatialGeometry.coverageScale(camera: camera, size: size)
                    #expect((scale - 1) * size.width / 2 > abs(camera.width) * 0.16 * scale)
                    #expect((scale - 1) * size.height / 2 > abs(camera.height) * 0.16 * scale)
                    for y in stride(from: CGFloat(0), through: 0.98, by: 0.02) {
                        for x in stride(from: CGFloat(0), through: 0.98, by: 0.02) {
                            let a = geometry.project(CGPoint(x: x, y: y), camera: camera, size: size)
                            let b = geometry.project(CGPoint(x: x + 0.01, y: y), camera: camera, size: size)
                            let c = geometry.project(CGPoint(x: x, y: y + 0.01), camera: camera, size: size)
                            #expect((b.x-a.x) * (c.y-a.y) - (b.y-a.y) * (c.x-a.x) > 0)
                        }
                    }
                }
            }
        }
    }
}

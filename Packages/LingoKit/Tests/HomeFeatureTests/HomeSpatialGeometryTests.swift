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
        #expect(london.depth(at: CGPoint(x: 0.15, y: 0.57)) == HomeSpatialGeometry.foregroundDepth)
        for layout in HomeDepartureSceneLayout.scenes.values {
            let geometry = HomeSpatialGeometry(assetName: layout.assetName)
            let center = CGPoint(x: geometry.opening.midX, y: geometry.opening.midY)
            #expect(geometry.depth(at: center) < 0.04)
            #expect(geometry.depth(at: CGPoint(x: 0.9, y: 0.4)) > 0.15)
            #expect(geometry.depth(at: CGPoint(x: 0.9, y: 0.98)) == HomeSpatialGeometry.foregroundDepth)
            #expect(geometry.project(center, camera: .zero, size: CGSize(width: 402, height: 874)) == center)
        }
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

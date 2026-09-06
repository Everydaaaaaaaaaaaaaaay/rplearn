import CoreGraphics
import DomainKit
import Testing
import UIKit
@testable import HomeFeature

@Suite("HomePerspectiveCalibration")
struct HomePerspectiveCalibrationTests {
    private let tolerance: CGFloat = 0.000_01

    @Test("城市入口的视觉和热区使用同一摄影承载面，且不越出有效内容")
    func citySceneGeometryIsBoundedAndInvertible() throws {
        for (id, layout) in HomeDepartureSceneLayout.scenes {
            for entry in [layout.location, layout.map, layout.story, layout.activities] {
                let visual = entry.projectedRegion()
                let hit = entry.projectedRegion(size: entry.hitSize)
                #expect(visual.surface.quad.points == hit.surface.quad.points)
                let inverse = try #require(visual.surface.homography.inverted)
                let center = CGPoint(x: entry.center.x, y: entry.center.y)
                expect(visual.surface.homography.project(inverse.project(center)), equals: center)
                for point in visual.photoQuad.points + hit.photoQuad.points {
                    #expect(point.x.isFinite && point.y.isFinite)
                    #expect(point.x >= 0 && point.x <= 1, "\(id) \(entry.surface): 水平方向越界")
                    #expect(point.y > 0.07, "\(id): 顶部安全区")
                    #expect(point.y * HomeDepartureCanvas.height <= HomeDepartureCanvas.interactiveContentBottom, "\(id): 底部安全区")
                }
            }
        }
    }

    @Test("全部可用城市均有独立、可解码的随包首页图")
    @MainActor
    func everyCatalogCityHasBundledScene() throws {
        let url = try #require(Bundle.main.url(forResource: "regions", withExtension: "json"))
        let catalog = try RegionCatalog(url: url)
        #expect(Set(catalog.regions.map(\.id)) == Set(HomeDepartureSceneLayout.scenes.keys))
        #expect(HomeDepartureSceneLayout.scenes.count == 15)
        for (id, layout) in HomeDepartureSceneLayout.scenes {
            let image = try #require(UIImage(named: layout.assetName, in: .main, compatibleWith: nil), "\(id): 缺失资源")
            #expect(image.size.width >= 800 && image.size.height >= 1800)
            #expect(abs(image.size.width / image.size.height - 853.0 / 1844.0) < 0.001)
        }
    }

    @Test("缺失城市安全回退，城市按稳定 ID 查找")
    func cityLookupUsesStableIDs() {
        #expect(HomeDepartureSceneLayout.forRegion(nil).assetName == HomeDepartureSceneLayout.production.assetName)
        #expect(HomeDepartureSceneLayout.forRegion("unknown").assetName == HomeDepartureSceneLayout.production.assetName)
        for (id, layout) in HomeDepartureSceneLayout.scenes {
            #expect(HomeDepartureSceneLayout.forRegion(id).assetName == layout.assetName)
        }
    }

    @Test("SE、标准屏和 Max 的入口不被底栏遮挡")
    func sceneFitsPhoneSizes() {
        for size in [CGSize(width: 375, height: 667), CGSize(width: 393, height: 852),
                     CGSize(width: 402, height: 874), CGSize(width: 440, height: 956)] {
            let placement = HomeDepartureCanvas.placement(in: size)
            for (id, layout) in HomeDepartureSceneLayout.scenes {
                for entry in [layout.map, layout.story, layout.activities] {
                    for point in entry.projectedRegion(size: entry.hitSize).photoQuad.points {
                        let x = point.x * HomeDepartureCanvas.width * placement.scale + placement.horizontalInset
                        let y = point.y * placement.height * placement.scale
                        #expect(x >= 0 && x <= size.width, "\(id): 横向裁切")
                        #expect(y >= 40 && y <= size.height - 84, "\(id): 状态栏或底栏遮挡")
                    }
                }
            }
        }
    }

    @Test("单应矩阵精确经过四个摄影标定角")
    func homographyMapsEveryCalibrationCorner() {
        for surface in [
            HomePerspectiveCalibration.production.doorLintel,
            HomePerspectiveCalibration.production.wall,
            HomePerspectiveCalibration.production.floor,
        ] {
            let unitCorners = [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 1, y: 0),
                CGPoint(x: 1, y: 1),
                CGPoint(x: 0, y: 1),
            ]
            for (source, expected) in zip(unitCorners, surface.quad.points) {
                expect(surface.homography.project(source), equals: expected)
            }
        }
    }

    @Test("照片坐标和平面坐标可稳定往返")
    func inverseRoundTripsEntryCenters() throws {
        let layout = HomeDepartureSceneLayout.production
        for entry in [layout.location, layout.map, layout.story, layout.activities] {
            let surface = HomePerspectiveCalibration.production.surface(entry.surface)
            let inverse = try #require(surface.homography.inverted)
            let photoPoint = CGPoint(x: entry.center.x, y: entry.center.y)
            let planePoint = inverse.project(photoPoint)
            expect(surface.homography.project(planePoint), equals: photoPoint)
        }
    }

    @Test("各入口使用对应的摄影承载面")
    func entriesUseTheirPhysicalSurface() {
        let layout = HomeDepartureSceneLayout.production
        #expect(layout.map.surface == .wall)
        #expect(layout.story.surface == .wall)
        #expect(layout.activities.surface == .floor)
        #expect(layout.location.surface == .doorLintel)

        for entry in [layout.location, layout.map, layout.story, layout.activities] {
            let points = entry.projectedRegion().photoQuad.points
            #expect(points.allSatisfy { $0.x.isFinite && $0.y.isFinite })
        }
    }

    private func expect(_ actual: CGPoint, equals expected: CGPoint) {
        #expect(abs(actual.x - expected.x) < tolerance)
        #expect(abs(actual.y - expected.y) < tolerance)
    }
}

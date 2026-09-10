import CoreGraphics
import DomainKit
import Testing
import UIKit
@testable import HomeFeature

@Suite("HomePerspectiveCalibration")
struct HomePerspectiveCalibrationTests {
    private let tolerance: CGFloat = 0.000_01

    @Test("重制背景使用新照片画框；同墙入口共享投影")
    func replacementMapFramesMatchPhotographicEdges() throws {
        // 独立观察的最终 JPEG 像素，防止退回旧图坐标。数值检查不代替视觉验收。
        for (id, width, height, leftX, leftY, rightX, rightY) in [
            ("london", 853.0, 1844.0, 514.0, 516.0, 844.0, 516.0),
            ("toronto", 853.0, 1844.0, 615.0, 422.0, 853.0, 328.0),
            ("edinburgh", 853.0, 1844.0, 515.0, 362.0, 829.0, 362.0),
        ] {
            let layout = try #require(HomeDepartureSceneLayout.scenes[id])
            let quad = layout.map.projectedRegion().surface.quad
            #expect(abs(quad.topLeft.x * width - leftX) < 3)
            #expect(abs(quad.topLeft.y * height - leftY) < 3)
            #expect(abs(quad.topRight.x * width - rightX) < 3)
            #expect(abs(quad.topRight.y * height - rightY) < 3)
        }
        for layout in HomeDepartureSceneLayout.scenes.values {
            #expect(layout.map.photoSurface?.quad.points == layout.story.photoSurface?.quad.points)
            #expect(layout.activities.surface == .floor)
        }
    }

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

    @Test("入口投影不能把图标文字压成横条")
    func projectedContentRetainsReadableHeight() {
        // 回归实际截图发现的爱丁堡地面过度剪切；可点击不能替代字形可读性。
        for (id, layout) in HomeDepartureSceneLayout.scenes {
            for entry in [layout.map, layout.story, layout.activities] {
                let q = entry.projectedRegion().photoQuad
                let top = (q.topLeft.y + q.topRight.y) / 2
                let bottom = (q.bottomLeft.y + q.bottomRight.y) / 2
                #expect((bottom - top) * HomeDepartureCanvas.height >= entry.renderSize.height * 0.7,
                        "\(id): 字形纵向投影小于原高度的 70%，需换可读的承载面")
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
            // Native crops retain >=2× the 402pt design canvas; never upscale to hit a pixel gate.
            #expect(image.size.width >= HomeDepartureCanvas.width * 2)
            #expect(image.size.height >= HomeDepartureCanvas.height * 2)
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
                    let hitPoints = entry.projectedRegion(size: entry.hitSize).photoQuad.points.map {
                        CGPoint(x: $0.x * HomeDepartureCanvas.width * placement.scale + placement.horizontalInset,
                                y: $0.y * placement.height * placement.scale)
                    }
                    let center = CGPoint(
                        x: entry.center.x * HomeDepartureCanvas.width * placement.scale + placement.horizontalInset,
                        y: entry.center.y * placement.height * placement.scale
                    )
                    // 验证 44×44pt 方形整个落在真实投影热区内，不能只看放大的外接矩形。
                    for offset in [CGPoint(x: -22, y: -22), CGPoint(x: 22, y: -22),
                                   CGPoint(x: 22, y: 22), CGPoint(x: -22, y: 22)] {
                        let point = CGPoint(x: center.x + offset.x, y: center.y + offset.y)
                        for index in 0..<4 {
                            let a = hitPoints[index], b = hitPoints[(index + 1) % 4]
                            let cross = (b.x - a.x) * (point.y - a.y) - (b.y - a.y) * (point.x - a.x)
                            #expect(cross >= 0, "\(id): 投影热区不足以包含 44×44pt")
                        }
                    }
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

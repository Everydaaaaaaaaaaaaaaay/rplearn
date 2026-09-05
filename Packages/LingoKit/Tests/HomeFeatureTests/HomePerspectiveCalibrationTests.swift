import CoreGraphics
import Testing
@testable import HomeFeature

@Suite("HomePerspectiveCalibration")
struct HomePerspectiveCalibrationTests {
    private let tolerance: CGFloat = 0.000_01

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

import CoreGraphics
import SwiftUI

/// 首页摄影母版与 Metal 投影层共享同一坐标系。
enum HomeDepartureCanvas {
    static let width: CGFloat = 402
    static let height: CGFloat = width * 1844 / 853

    /// 最低入口位于画布约 72% 处；短屏按这段有效内容整体缩放。
    static let interactiveContentBottom: CGFloat = 760
}

enum HomeSceneEntryID: String, CaseIterable, Sendable {
    case map
    case story
    case activities
}

/// 摄影母版中经过一次性标定的承载平面。生产渲染只读取这些固定数据，
/// 不在运行时重新分析或改写背景图片。
enum HomePhotoSurfaceID: String, Sendable {
    case screen
    case doorLintel
    case wall
    case floor
}

struct HomeSurfacePose: Sendable {
    let name: String
    let pitch: Double
    let yaw: Double
    let roll: Double
}

/// 单位正方形四角在摄影母版中的归一化坐标，顺序为左上、右上、右下、左下。
struct HomePerspectiveQuad: Sendable {
    let topLeft: CGPoint
    let topRight: CGPoint
    let bottomRight: CGPoint
    let bottomLeft: CGPoint

    var points: [CGPoint] {
        [topLeft, topRight, bottomRight, bottomLeft]
    }
}

/// 将平面坐标 (u, v) 映射到照片坐标 (x, y) 的 3×3 单应矩阵。
/// 这是视觉共面的唯一几何来源；姿态角只用于校准面板中的可读标注。
struct HomeHomography: Sendable {
    let a: CGFloat
    let b: CGFloat
    let c: CGFloat
    let d: CGFloat
    let e: CGFloat
    let f: CGFloat
    let g: CGFloat
    let h: CGFloat
    let i: CGFloat

    static let identity = HomeHomography(
        a: 1, b: 0, c: 0,
        d: 0, e: 1, f: 0,
        g: 0, h: 0, i: 1
    )

    init(
        a: CGFloat,
        b: CGFloat,
        c: CGFloat,
        d: CGFloat,
        e: CGFloat,
        f: CGFloat,
        g: CGFloat,
        h: CGFloat,
        i: CGFloat
    ) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
        self.e = e
        self.f = f
        self.g = g
        self.h = h
        self.i = i
    }

    init(quad: HomePerspectiveQuad) {
        let p0 = quad.topLeft
        let p1 = quad.topRight
        let p2 = quad.bottomRight
        let p3 = quad.bottomLeft
        let dx1 = p1.x - p2.x
        let dx2 = p3.x - p2.x
        let dx3 = p0.x - p1.x + p2.x - p3.x
        let dy1 = p1.y - p2.y
        let dy2 = p3.y - p2.y
        let dy3 = p0.y - p1.y + p2.y - p3.y
        let determinant = dx1 * dy2 - dx2 * dy1

        guard abs(determinant) > 0.000_000_1 else {
            self = .identity
            return
        }

        let projectiveX = (dx3 * dy2 - dx2 * dy3) / determinant
        let projectiveY = (dx1 * dy3 - dx3 * dy1) / determinant
        self.init(
            a: p1.x - p0.x + projectiveX * p1.x,
            b: p3.x - p0.x + projectiveY * p3.x,
            c: p0.x,
            d: p1.y - p0.y + projectiveX * p1.y,
            e: p3.y - p0.y + projectiveY * p3.y,
            f: p0.y,
            g: projectiveX,
            h: projectiveY,
            i: 1
        )
    }

    func project(_ point: CGPoint) -> CGPoint {
        let denominator = g * point.x + h * point.y + i
        guard abs(denominator) > 0.000_000_1 else { return .zero }
        return CGPoint(
            x: (a * point.x + b * point.y + c) / denominator,
            y: (d * point.x + e * point.y + f) / denominator
        )
    }

    var inverted: HomeHomography? {
        let determinant = a * (e * i - f * h)
            - b * (d * i - f * g)
            + c * (d * h - e * g)
        guard abs(determinant) > 0.000_000_1 else { return nil }
        return HomeHomography(
            a: (e * i - f * h) / determinant,
            b: (c * h - b * i) / determinant,
            c: (b * f - c * e) / determinant,
            d: (f * g - d * i) / determinant,
            e: (a * i - c * g) / determinant,
            f: (c * d - a * f) / determinant,
            g: (d * h - e * g) / determinant,
            h: (b * g - a * h) / determinant,
            i: (a * e - b * d) / determinant
        )
    }
}

struct HomePhotoSurface: Sendable {
    let id: HomePhotoSurfaceID
    let quad: HomePerspectiveQuad
    let pose: HomeSurfacePose
    let homography: HomeHomography

    init(id: HomePhotoSurfaceID, quad: HomePerspectiveQuad, pose: HomeSurfacePose) {
        self.id = id
        self.quad = quad
        self.pose = pose
        homography = HomeHomography(quad: quad)
    }
}

struct HomePerspectiveCalibration: Sendable {
    let screen: HomePhotoSurface
    let doorLintel: HomePhotoSurface
    let wall: HomePhotoSurface
    let floor: HomePhotoSurface

    func surface(_ id: HomePhotoSurfaceID) -> HomePhotoSurface {
        switch id {
        case .screen: screen
        case .doorLintel: doorLintel
        case .wall: wall
        case .floor: floor
        }
    }

    /// 四角均在 853 × 1844 的一次性生产底图上测量。
    /// 上门框以白色横梁四边为基准，墙面以纸质地图为矩形基准，
    /// 地面以门口地垫为矩形基准。
    static let production = HomePerspectiveCalibration(
        screen: HomePhotoSurface(
            id: .screen,
            quad: HomePerspectiveQuad(
                topLeft: CGPoint(x: 0, y: 0),
                topRight: CGPoint(x: 1, y: 0),
                bottomRight: CGPoint(x: 1, y: 1),
                bottomLeft: CGPoint(x: 0, y: 1)
            ),
            pose: HomeSurfacePose(name: "屏幕平面", pitch: 0, yaw: 0, roll: 0)
        ),
        doorLintel: HomePhotoSurface(
            id: .doorLintel,
            quad: HomePerspectiveQuad(
                topLeft: CGPoint(x: 0.0 / 853.0, y: 153.0 / 1844.0),
                topRight: CGPoint(x: 370.0 / 853.0, y: 234.0 / 1844.0),
                bottomRight: CGPoint(x: 340.0 / 853.0, y: 265.0 / 1844.0),
                bottomLeft: CGPoint(x: 0.0 / 853.0, y: 198.0 / 1844.0)
            ),
            pose: HomeSurfacePose(name: "上门框", pitch: -5, yaw: 14, roll: 12)
        ),
        wall: HomePhotoSurface(
            id: .wall,
            quad: HomePerspectiveQuad(
                topLeft: CGPoint(x: 453.0 / 853.0, y: 352.0 / 1844.0),
                topRight: CGPoint(x: 744.0 / 853.0, y: 250.0 / 1844.0),
                bottomRight: CGPoint(x: 744.0 / 853.0, y: 682.0 / 1844.0),
                bottomLeft: CGPoint(x: 453.0 / 853.0, y: 661.0 / 1844.0)
            ),
            pose: HomeSurfacePose(name: "右侧墙面", pitch: -2, yaw: -17, roll: -8)
        ),
        floor: HomePhotoSurface(
            id: .floor,
            quad: HomePerspectiveQuad(
                topLeft: CGPoint(x: 14.0 / 853.0, y: 1147.0 / 1844.0),
                topRight: CGPoint(x: 284.0 / 853.0, y: 1118.0 / 1844.0),
                bottomRight: CGPoint(x: 312.0 / 853.0, y: 1217.0 / 1844.0),
                bottomLeft: CGPoint(x: 0, y: 1293.0 / 1844.0)
            ),
            pose: HomeSurfacePose(name: "入口地面", pitch: -58, yaw: 4, roll: -7)
        )
    )
}

struct HomeProjectedRegion: Sendable {
    let surface: HomePhotoSurface
    let planeCenter: CGPoint
    let planeSize: CGSize

    var photoQuad: HomePerspectiveQuad {
        let halfWidth = planeSize.width / 2
        let halfHeight = planeSize.height / 2
        let transform = surface.homography
        return HomePerspectiveQuad(
            topLeft: transform.project(CGPoint(x: planeCenter.x - halfWidth, y: planeCenter.y - halfHeight)),
            topRight: transform.project(CGPoint(x: planeCenter.x + halfWidth, y: planeCenter.y - halfHeight)),
            bottomRight: transform.project(CGPoint(x: planeCenter.x + halfWidth, y: planeCenter.y + halfHeight)),
            bottomLeft: transform.project(CGPoint(x: planeCenter.x - halfWidth, y: planeCenter.y + halfHeight))
        )
    }
}

struct HomeDepartureHotspotLayout: Sendable {
    let center: UnitPoint
    let hitSize: CGSize
    let renderSize: CGSize
    let surface: HomePhotoSurfaceID

    func projectedRegion(
        size requestedSize: CGSize? = nil,
        calibration: HomePerspectiveCalibration = .production
    ) -> HomeProjectedRegion {
        let target = CGPoint(x: center.x, y: center.y)
        let surface = calibration.surface(self.surface)
        guard let inverse = surface.homography.inverted else {
            return HomeProjectedRegion(surface: surface, planeCenter: target, planeSize: .zero)
        }

        let planeCenter = inverse.project(target)
        let epsilon: CGFloat = 0.001
        let origin = surface.homography.project(planeCenter)
        let horizontal = surface.homography.project(
            CGPoint(x: planeCenter.x + epsilon, y: planeCenter.y)
        )
        let vertical = surface.homography.project(
            CGPoint(x: planeCenter.x, y: planeCenter.y + epsilon)
        )
        let horizontalScale = max(hypot(horizontal.x - origin.x, horizontal.y - origin.y) / epsilon, 0.0001)
        let verticalScale = max(hypot(vertical.x - origin.x, vertical.y - origin.y) / epsilon, 0.0001)
        let requestedSize = requestedSize ?? renderSize
        let normalizedSize = CGSize(
            width: requestedSize.width / HomeDepartureCanvas.width,
            height: requestedSize.height / HomeDepartureCanvas.height
        )
        return HomeProjectedRegion(
            surface: surface,
            planeCenter: planeCenter,
            planeSize: CGSize(
                width: normalizedSize.width / horizontalScale,
                height: normalizedSize.height / verticalScale
            )
        )
    }
}

struct HomeDepartureSceneLayout: Sendable {
    let assetName: String
    let location: HomeDepartureHotspotLayout
    let map: HomeDepartureHotspotLayout
    let story: HomeDepartureHotspotLayout
    let activities: HomeDepartureHotspotLayout

    /// 坐标按 853 × 1844 的一次性生产底图逐入口测量；所有角度都由承载面的
    /// 固定单应矩阵统一产生，不再保留逐入口手调角度。
    static let production = HomeDepartureSceneLayout(
        assetName: "home_departure_foyer",
        location: .init(
            center: UnitPoint(x: 0.215, y: 0.12),
            hitSize: CGSize(width: 142, height: 82),
            renderSize: CGSize(width: 142, height: 82),
            surface: .doorLintel
        ),
        map: .init(
            center: UnitPoint(x: 0.68, y: 0.19),
            hitSize: CGSize(width: 132, height: 126),
            renderSize: CGSize(width: 140, height: 132),
            surface: .wall
        ),
        story: .init(
            center: UnitPoint(x: 0.62, y: 0.49),
            hitSize: CGSize(width: 146, height: 132),
            renderSize: CGSize(width: 154, height: 140),
            surface: .wall
        ),
        activities: .init(
            center: UnitPoint(x: 0.25, y: 0.70),
            hitSize: CGSize(width: 148, height: 126),
            renderSize: CGSize(width: 144, height: 88),
            surface: .floor
        )
    )
}

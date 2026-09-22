import SwiftUI

/// 人工标定的相对深度，不代表照片包含真实测距数据。静止时严格还原原图。
enum MyPageSpatialGeometry {
    static let size = CGSize(width: TravelDeskLayout.canvasWidth, height: TravelDeskLayout.canvasHeight)
    static let cameraLimit: CGFloat = 32

    struct Surface {
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
        let height: CGFloat
        let angle: CGFloat
        let relief: CGFloat

        func weight(at point: CGPoint) -> CGFloat {
            let dx = point.x * 825 - x
            let dy = point.y * 1906 - y
            let radians = angle * .pi / 180
            let u = abs(dx * cos(radians) + dy * sin(radians)) - width / 2
            let v = abs(-dx * sin(radians) + dy * cos(radians)) - height / 2
            // 物体内保持刚性平面；轮廓附近柔和过渡，限制露底与撕裂。
            let t = min(max((max(u, v) + 6) / 48, 0), 1)
            return 1 - t * t * (3 - 2 * t)
        }
    }

    static let surfaces: [Surface] = [
        .init(x: 166, y: 333, width: 286, height: 222, angle: -12, relief: 0.13),
        .init(x: 441, y: 424, width: 197, height: 140, angle: 6, relief: 0.31),
        .init(x: 690, y: 364, width: 172, height: 152, angle: 18, relief: 0.19),
        .init(x: 412, y: 930, width: 268, height: 424, angle: 0.8, relief: 0.13),
        .init(x: 166, y: 1440, width: 226, height: 330, angle: -11.8, relief: 0.21),
        .init(x: 419, y: 1508, width: 135, height: 296, angle: 0.3, relief: 0.14),
        .init(x: 610, y: 1530, width: 76, height: 526, angle: 14.5, relief: 0.12),
        .init(x: 626, y: 1495, width: 84, height: 102, angle: 14.5, relief: 0.22),
        .init(x: 721, y: 1550, width: 87, height: 99, angle: 17, relief: 0.27),
    ]

    static func depth(at point: CGPoint) -> CGFloat {
        let relief = surfaces.map { $0.relief * $0.weight(at: point) }.max() ?? 0
        let edge = min(min(point.x, 1 - point.x) / 0.05, min(point.y, 1 - point.y) / 0.025)
        let t = min(max(edge, 0), 1)
        return 0.06 + 0.05 * point.y + relief * t * t * (3 - 2 * t)
    }

    static func displacement(at point: UnitPoint, camera: CGSize, floating: Bool = false) -> CGSize {
        let depth = depth(at: CGPoint(x: point.x, y: point.y)) + (floating ? 0.025 : 0)
        return CGSize(width: camera.width * depth, height: camera.height * depth)
    }

    static func resisted(_ translation: CGSize) -> CGSize {
        let distance = hypot(translation.width, translation.height)
        let factor = 0.55 / (1 + distance * 0.55 / cameraLimit)
        return CGSize(width: translation.width * factor, height: translation.height * factor)
    }

    /// 重新抓取回弹时，由当前显示位置恢复手势原点，避免跳回逻辑零点。
    static func unresisted(_ camera: CGSize) -> CGSize {
        let distance = min(hypot(camera.width, camera.height), cameraLimit - 0.01)
        let factor = 1 / (0.55 * (1 - distance / cameraLimit))
        return CGSize(width: camera.width * factor, height: camera.height * factor)
    }

    static func coverageScale(camera: CGSize) -> CGFloat {
        // 图像边缘仅有桌面深度；统一缩放也作用于入口和命中区域。
        1 + max(abs(camera.width) * 0.12 / size.width, abs(camera.height) * 0.12 / size.height) * 2
    }
}

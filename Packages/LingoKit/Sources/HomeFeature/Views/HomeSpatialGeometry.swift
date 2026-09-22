import SwiftUI
import DesignSystem

/// 按当前十五张城市母版标定门内远景范围；不是相机测距，也不重建遮挡背面。
struct HomeSpatialGeometry {
    let opening: CGRect
    private let city: String

    init(assetName: String) {
        city = assetName.replacingOccurrences(of: "home_city_", with: "")
        let values = Self.calibrations[city] ?? Self.calibrations["london"]!
        opening = CGRect(x: values[0], y: values[1], width: values[2] - values[0], height: values[3] - values[1]).insetBy(dx: 0.008, dy: 0.005)
    }

    // 左、上、右、下（第五项保留旧标定中的地面起点，不再用于形变）；基于最终 JPEG 的归一化坐标。
    static let calibrations: [String: [CGFloat]] = [
        "auckland": [0.14, 0.27, 0.43, 0.60, 0.64],
        "capetown": [0.10, 0.20, 0.44, 0.66, 0.73],
        "dublin": [0.11, 0.25, 0.40, 0.58, 0.63],
        "edinburgh": [0.10, 0.17, 0.44, 0.63, 0.69],
        "kingston": [0.11, 0.26, 0.42, 0.60, 0.66],
        "london": [0.125, 0.19, 0.455, 0.663, 0.70],
        "manchester": [0.10, 0.19, 0.44, 0.63, 0.70],
        "melbourne": [0.09, 0.18, 0.41, 0.59, 0.68],
        "nairobi": [0.11, 0.24, 0.45, 0.635, 0.66],
        "neworleans": [0.095, 0.24, 0.43, 0.65, 0.71],
        "newyork": [0.095, 0.22, 0.425, 0.59, 0.66],
        "singapore": [0.10, 0.235, 0.45, 0.65, 0.70],
        "sydney": [0.13, 0.295, 0.435, 0.64, 0.69],
        "toronto": [0.09, 0.205, 0.44, 0.585, 0.65],
        "vancouver": [0.12, 0.29, 0.44, 0.65, 0.69],
    ]

    static let foregroundDepth: CGFloat = 0.16
    static let backgroundDepth: CGFloat = 0.03

    var layers: [DSSceneParallaxLayer] {
        var contour = [
            CGPoint(x: opening.minX, y: opening.minY), CGPoint(x: opening.maxX, y: opening.minY),
            CGPoint(x: opening.maxX, y: opening.maxY), CGPoint(x: opening.minX, y: opening.maxY),
        ]
        if city == "london" {
            // 玻璃内侧切分；门把手与左下方室内植物仍归属完整室内层。
            contour = [
                CGPoint(x: opening.minX, y: opening.minY), CGPoint(x: opening.maxX, y: opening.minY),
                CGPoint(x: opening.maxX, y: 0.468), CGPoint(x: 0.424, y: 0.468),
                CGPoint(x: 0.424, y: 0.485), CGPoint(x: opening.maxX, y: 0.485),
                CGPoint(x: opening.maxX, y: opening.maxY), CGPoint(x: opening.minX, y: opening.maxY),
                CGPoint(x: opening.minX, y: 0.628), CGPoint(x: 0.175, y: 0.615),
                CGPoint(x: 0.175, y: 0.540), CGPoint(x: opening.minX, y: 0.518),
            ]
        }
        return [DSSceneParallaxLayer(contour: contour, depth: Self.foregroundDepth, inverted: true)]
    }

    func depth(at p: CGPoint) -> CGFloat {
        layers[0].contains(p) ? Self.foregroundDepth : Self.backgroundDepth
    }

    func project(_ point: CGPoint, camera: CGSize, size: CGSize) -> CGPoint {
        // 所有入口属于完整室内前景，不在门玻璃的深度断面上插值。
        let d = Self.foregroundDepth
        return CGPoint(x: point.x + camera.width * d / size.width,
                       y: point.y + camera.height * d / size.height)
    }

    func project(_ quad: HomePerspectiveQuad, camera: CGSize, size: CGSize) -> HomePerspectiveQuad {
        HomePerspectiveQuad(topLeft: project(quad.topLeft, camera: camera, size: size),
                            topRight: project(quad.topRight, camera: camera, size: size),
                            bottomRight: project(quad.bottomRight, camera: camera, size: size),
                            bottomLeft: project(quad.bottomLeft, camera: camera, size: size))
    }

    static func coverageScale(camera: CGSize, size: CGSize) -> CGFloat {
        1 + max(abs(camera.width) / size.width, abs(camera.height) / size.height) * 0.36
    }
}

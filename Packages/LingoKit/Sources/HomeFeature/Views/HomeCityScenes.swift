import CoreGraphics
import SwiftUI

/// 与 Assets/HomeScenes/generation-manifest.json 中通过验收的母图一一对应。
/// 各入口四角以母图归一化坐标保存，复用首页既有单应矩阵和 Metal 材质。
extension HomeDepartureSceneLayout {
    static var production: Self { scenes["london"]! }

    static func forRegion(_ regionID: String?) -> Self {
        regionID.flatMap { scenes[$0] } ?? production
    }

    static let scenes: [String: Self] = [
        "london": .init(
            assetName: "home_city_london",
            location: measured(.doorLintel, center: [0.405, 0.14222], size: [142, 70],
                          quad: [0.2, 0.11917, 0.63, 0.11917, 0.63, 0.16928, 0.2, 0.16928]),
            map: measured(.wall, center: [0.845, 0.32462], size: [110, 126],
                          quad: [0.703, 0.2244, 0.98, 0.2214, 0.98, 0.41882, 0.703, 0.41582]),
            story: measured(.wall, center: [0.81, 0.52906], size: [134, 140],
                          quad: [0.703, 0.2244, 0.98, 0.2214, 0.98, 0.41882, 0.703, 0.41582]),
            activities: measured(.floor, center: [0.395, 0.80566], size: [144, 90],
                          quad: [0.23, 0.75555, 0.57, 0.75756, 0.64, 0.8708, 0.09, 0.8708])
        ),
        "melbourne": .init(
            assetName: "home_city_melbourne",
            location: measured(.doorLintel, center: [0.33148, 0.132], size: [142, 70],
                          quad: [0.08126, 0.135, 0.59192, 0.147, 0.59192, 0.173, 0.08126, 0.162]),
            map: measured(.wall, center: [0.85338, 0.313], size: [104, 126],
                          quad: [0.71448, 0.151, 1.01066, 0.143, 1.01066, 0.438, 0.71448, 0.417]),
            story: measured(.wall, center: [0.80333, 0.534], size: [134, 132],
                          quad: [0.71448, 0.151, 1.01066, 0.143, 1.01066, 0.438, 0.71448, 0.417]),
            activities: measured(.door, center: [0.33148, 0.658], size: [144, 90],
                          quad: [0.10168, 0.174, 0.56128, 0.184, 0.55617, 0.763, 0.10168, 0.787])
        ),
        "newyork": .init(
            assetName: "home_city_newyork",
            location: measured(.doorLintel, center: [0.27531, 0.13], size: [142, 70],
                          quad: [-0.00045, 0.1, 0.54085, 0.1, 0.54085, 0.14, -0.00045, 0.14]),
            map: measured(.wall, center: [0.75533, 0.29], size: [132, 126],
                          quad: [0.5429, 0.208, 0.9647, 0.208, 0.9647, 0.375, 0.5429, 0.375]),
            story: measured(.wall, center: [0.75533, 0.437], size: [140, 132],
                          quad: [0.5429, 0.208, 0.9647, 0.208, 0.9647, 0.375, 0.5429, 0.375]),
            activities: measured(.floor, center: [0.29573, 0.785], size: [144, 90],
                          quad: [0.07104, 0.76, 0.5, 0.76, 0.60213, 0.9, -0.01066, 0.9])
        ),
        "capetown": .init(
            assetName: "home_city_capetown",
            location: measured(.doorLintel, center: [0.3362, 0.14], size: [142, 70],
                          quad: [0.12122, 0.11, 0.53583, 0.145, 0.53583, 0.163, 0.12122, 0.128]),
            map: measured(.wall, center: [0.82247, 0.294], size: [110, 126],
                          quad: [0.68632, 0.194, 1.01186, 0.105, 1.01186, 0.387, 0.68632, 0.394]),
            story: measured(.wall, center: [0.77845, 0.49], size: [130, 132],
                          quad: [0.68632, 0.194, 1.01186, 0.105, 1.01186, 0.387, 0.68632, 0.394]),
            activities: measured(.floor, center: [0.32597, 0.79], size: [144, 90],
                          quad: [0.22359, 0.706, 0.54095, 0.69, 0.61261, 0.884, 0.00861, 0.94])
        ),
        "singapore": .init(
            assetName: "home_city_singapore",
            location: measured(.doorLintel, center: [0.28, 0.125], size: [142, 70],
                          quad: [0.01, 0.08, 0.54, 0.08, 0.54, 0.14, 0.01, 0.14]),
            map: measured(.wall, center: [0.806, 0.31], size: [132, 126],
                          quad: [0.61, 0.22, 0.99, 0.219, 0.99, 0.401, 0.61, 0.401]),
            story: measured(.wall, center: [0.79, 0.465], size: [140, 132],
                          quad: [0.61, 0.22, 0.99, 0.219, 0.99, 0.401, 0.61, 0.401]),
            activities: measured(.floor, center: [0.32, 0.8], size: [144, 90],
                          quad: [0.12, 0.78, 0.55, 0.78, 0.63, 0.9, 0.02, 0.9])
        ),
        "dublin": .init(
            assetName: "home_city_dublin",
            location: measured(.doorLintel, center: [0.21268, 0.273], size: [142, 70],
                          quad: [-0.01306, 0.245, 0.39431, 0.259, 0.39431, 0.29, -0.01306, 0.28]),
            map: measured(.wall, center: [0.8417, 0.35], size: [110, 126],
                          quad: [0.67444, 0.22, 1.01306, 0.202, 1.01306, 0.49, 0.67444, 0.467]),
            story: measured(.wall, center: [0.79758, 0.56], size: [134, 132],
                          quad: [0.67444, 0.22, 1.01306, 0.202, 1.01306, 0.49, 0.67444, 0.467]),
            activities: measured(.floor, center: [0.32556, 0.798], size: [144, 90],
                          quad: [0.09981, 0.768, 0.5, 0.767, 0.65392, 0.89, -0.01306, 0.9])
        ),
        "edinburgh": .init(
            assetName: "home_city_edinburgh",
            location: measured(.doorLintel, center: [0.725, 0.145], size: [142, 70],
                          quad: [0.46, 0.126, 0.98, 0.126, 0.98, 0.163, 0.46, 0.163]),
            map: measured(.wall, center: [0.183, 0.39], size: [110, 126],
                          quad: [0, 0.257, 0.367, 0.278, 0.367, 0.514, 0, 0.535]),
            story: measured(.wall, center: [0.196, 0.606], size: [132, 132],
                          quad: [0, 0.257, 0.367, 0.278, 0.367, 0.514, 0, 0.535]),
            activities: measured(.door, center: [0.725, 0.665], size: [144, 90],
                          quad: [0.485, 0.175, 0.963, 0.175, 0.963, 0.781, 0.502, 0.782])
        ),
        "vancouver": .init(
            assetName: "home_city_vancouver",
            location: measured(.doorLintel, center: [0.69963, 0.145], size: [142, 70],
                          quad: [0.44881, 0.124, 0.96068, 0.124, 0.96068, 0.164, 0.44881, 0.164]),
            map: measured(.wall, center: [0.18265, 0.295], size: [128, 126],
                          quad: [-0.01186, 0.205, 0.38739, 0.208, 0.38739, 0.386, -0.01186, 0.394]),
            story: measured(.wall, center: [0.198, 0.508], size: [142, 140],
                          quad: [-0.01186, 0.205, 0.38739, 0.208, 0.38739, 0.386, -0.01186, 0.394]),
            activities: measured(.floor, center: [0.6638, 0.81], size: [144, 90],
                          quad: [0.47953, 0.76, 0.90949, 0.76, 1.00163, 0.89, 0.36692, 0.89])
        ),
        "auckland": .init(
            assetName: "home_city_auckland",
            location: measured(.doorLintel, center: [0.2702, 0.212], size: [142, 70],
                          quad: [0.03019, 0.193, 0.51021, 0.2, 0.51021, 0.24, 0.03019, 0.234]),
            map: measured(.wall, center: [0.78597, 0.355], size: [140, 126],
                          quad: [0.54596, 0.249, 1.01066, 0.244, 1.01066, 0.47, 0.54596, 0.466]),
            story: measured(.wall, center: [0.78597, 0.165], size: [140, 126],
                          quad: [0.54596, 0.249, 1.01066, 0.244, 1.01066, 0.47, 0.54596, 0.466]),
            activities: measured(.floor, center: [0.29573, 0.809], size: [144, 90],
                          quad: [0.08126, 0.765, 0.53064, 0.765, 0.61235, 0.891, -0.00045, 0.891])
        ),
        "nairobi": .init(
            assetName: "home_city_nairobi",
            location: measured(.doorLintel, center: [0.755, 0.20315], size: [142, 70],
                          quad: [0.5, 0.18307, 0.98, 0.18307, 0.98, 0.22423, 0.5, 0.22423]),
            map: measured(.wall, center: [0.25, 0.33163], size: [150, 126],
                          quad: [0, 0.23928, 0.485, 0.23828, 0.485, 0.42599, 0, 0.42699]),
            story: measured(.wall, center: [0.29, 0.51031], size: [148, 132],
                          quad: [0, 0.23928, 0.485, 0.23828, 0.485, 0.42599, 0, 0.42699]),
            activities: measured(.floor, center: [0.72, 0.81346], size: [144, 90],
                          quad: [0.52, 0.7703, 0.95, 0.7713, 1, 0.89778, 0.41, 0.89778])
        ),
        "toronto": .init(
            assetName: "home_city_toronto",
            location: measured(.doorLintel, center: [0.30504, 0.191], size: [142, 70],
                          quad: [0.06903, 0.175, 0.54105, 0.183, 0.54105, 0.216, 0.06903, 0.208]),
            map: measured(.wall, center: [0.82836, 0.313], size: [112, 126],
                          quad: [0.65905, 0.237, 1.01306, 0.217, 1.01306, 0.41, 0.65905, 0.408]),
            story: measured(.wall, center: [0.80784, 0.488], size: [140, 132],
                          quad: [0.65905, 0.237, 1.01306, 0.217, 1.01306, 0.41, 0.65905, 0.408]),
            activities: measured(.door, center: [0.29477, 0.645], size: [144, 90],
                          quad: [0.09365, 0.198, 0.50616, 0.205, 0.50616, 0.718, 0.09365, 0.727])
        ),
        "sydney": .init(
            assetName: "home_city_sydney",
            location: measured(.doorLintel, center: [0.29, 0.21], size: [142, 70],
                          quad: [0.07, 0.194, 0.55, 0.195, 0.55, 0.231, 0.07, 0.23]),
            map: measured(.wall, center: [0.8, 0.355], size: [128, 126],
                          quad: [0.604, 0.26, 1, 0.245, 1, 0.447, 0.604, 0.443]),
            story: measured(.wall, center: [0.8, 0.168], size: [140, 140],
                          quad: [0.604, 0.26, 1, 0.245, 1, 0.447, 0.604, 0.443]),
            activities: measured(.floor, center: [0.34, 0.802], size: [144, 90],
                          quad: [0.14, 0.77, 0.57, 0.77, 0.66, 0.9, 0.03, 0.9])
        ),
        "neworleans": .init(
            assetName: "home_city_neworleans",
            location: measured(.doorLintel, center: [0.725, 0.15926], size: [142, 70],
                          quad: [0.468, 0.14623, 0.98, 0.14623, 0.98, 0.16828, 0.468, 0.16828]),
            map: measured(.wall, center: [0.186, 0.34967], size: [120, 126],
                          quad: [0, 0.26249, 0.337, 0.26349, 0.337, 0.44187, 0, 0.44187]),
            story: measured(.wall, center: [0.215, 0.51002], size: [142, 132],
                          quad: [0, 0.26249, 0.337, 0.26349, 0.337, 0.44187, 0, 0.44187]),
            activities: measured(.floor, center: [0.64, 0.80266], size: [144, 90],
                          quad: [0.43, 0.7746, 0.86, 0.7746, 0.96, 0.89987, 0.33, 0.89987])
        ),
        "manchester": .init(
            assetName: "home_city_manchester",
            location: measured(.doorLintel, center: [0.338, 0.165], size: [142, 70],
                          quad: [0.12, 0.151, 0.548, 0.156, 0.548, 0.181, 0.12, 0.176]),
            map: measured(.wall, center: [0.836, 0.264], size: [112, 126],
                          quad: [0.666, 0.153, 1, 0.095, 1, 0.356, 0.666, 0.363]),
            story: measured(.wall, center: [0.79, 0.476], size: [140, 140],
                          quad: [0.666, 0.153, 1, 0.095, 1, 0.356, 0.666, 0.363]),
            activities: measured(.floor, center: [0.34, 0.81], size: [144, 90],
                          quad: [0.14, 0.77, 0.57, 0.77, 0.68, 0.9, 0.02, 0.9])
        ),
        "kingston": .init(
            assetName: "home_city_kingston",
            location: measured(.doorLintel, center: [0.755, 0.19], size: [142, 70],
                          quad: [0.53, 0.187, 0.963, 0.167, 0.963, 0.204, 0.53, 0.224]),
            map: measured(.wall, center: [0.18, 0.309], size: [112, 126],
                          quad: [0, 0.15, 0.342, 0.224, 0.342, 0.439, 0, 0.454]),
            story: measured(.wall, center: [0.23, 0.52], size: [140, 132],
                          quad: [0, 0.15, 0.342, 0.224, 0.342, 0.439, 0, 0.454]),
            activities: measured(.floor, center: [0.72, 0.818], size: [144, 90],
                          quad: [0.53, 0.706, 0.97, 0.727, 0.84, 0.9, 0.17, 0.866])
        ),
    ]

    private static func measured(
        _ surfaceID: HomePhotoSurfaceID,
        center: [CGFloat], size: [CGFloat], quad: [CGFloat]
    ) -> HomeDepartureHotspotLayout {
        let surface = HomePhotoSurface(
            id: surfaceID,
            quad: HomePerspectiveQuad(
                topLeft: CGPoint(x: quad[0], y: quad[1]),
                topRight: CGPoint(x: quad[2], y: quad[3]),
                bottomRight: CGPoint(x: quad[4], y: quad[5]),
                bottomLeft: CGPoint(x: quad[6], y: quad[7])
            ),
            // 实际视觉几何来自四角；不以手写欧拉角代替照片标定。
            pose: HomeSurfacePose(name: surfaceID.rawValue, pitch: 0, yaw: 0, roll: 0)
        )
        return HomeDepartureHotspotLayout(
            center: UnitPoint(x: center[0], y: center[1]),
            hitSize: CGSize(width: max(size[0], 88), height: max(size[1], 88)),
            renderSize: CGSize(width: size[0], height: size[1]),
            surface: surfaceID,
            photoSurface: surface
        )
    }
}

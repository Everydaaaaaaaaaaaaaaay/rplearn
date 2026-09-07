import CoreGraphics
import SwiftUI

/// 与 Assets/HomeScenes/generation-manifest.json 中通过验收的母图一一对应。
/// 标定依据是最终裁切 JPEG，像素见 perspective-landmarks.json；不是未裁切母图。
/// 地图与同墙剧情共享单应矩阵，图标/文字/热区整体投影；不要用旋转角替代标定。
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
                          quad: [0.7042254, 0.218241, 1, 0.2149837, 1, 0.4234528, 0.6995305, 0.422367]),
            story: measured(.wall, center: [0.81, 0.52906], size: [134, 140],
                          quad: [0.7042254, 0.218241, 1, 0.2149837, 1, 0.4234528, 0.6995305, 0.422367]),
            activities: measured(.floor, center: [0.395, 0.80566], size: [144, 90],
                          quad: [0.23, 0.75555, 0.57, 0.75756, 0.64, 0.8708, 0.09, 0.8708])
        ),
        "melbourne": .init(
            assetName: "home_city_melbourne",
            location: measured(.doorLintel, center: [0.33148, 0.132], size: [142, 70],
                          quad: [0.08126, 0.135, 0.59192, 0.147, 0.59192, 0.173, 0.08126, 0.162]),
            map: measured(.wall, center: [0.83338, 0.313], size: [104, 126],
                          quad: [0.7132701, 0.254386, 1, 0.1578947, 1, 0.4270833, 0.714455, 0.4375]),
            story: measured(.wall, center: [0.77333, 0.534], size: [134, 132],
                          quad: [0.7132701, 0.254386, 1, 0.1578947, 1, 0.4270833, 0.714455, 0.4375]),
            activities: measured(.door, center: [0.33148, 0.658], size: [144, 90],
                          quad: [0.1682464, 0.5778509, 0.4917062, 0.5734649, 0.4917062, 0.7121711, 0.1682464, 0.723136])
        ),
        "newyork": .init(
            assetName: "home_city_newyork",
            location: measured(.doorLintel, center: [0.27531, 0.13], size: [142, 70],
                          quad: [-0.00045, 0.1, 0.54085, 0.1, 0.54085, 0.14, -0.00045, 0.14]),
            map: measured(.wall, center: [0.75533, 0.29], size: [132, 126],
                          quad: [0.5438389, 0.2088816, 0.964455, 0.2083333, 0.9632701, 0.3744518, 0.5438389, 0.375]),
            story: measured(.wall, center: [0.75533, 0.437], size: [140, 132],
                          quad: [0.5438389, 0.2088816, 0.964455, 0.2083333, 0.9632701, 0.3744518, 0.5438389, 0.375]),
            activities: measured(.floor, center: [0.29573, 0.785], size: [144, 90],
                          quad: [0.07104, 0.76, 0.5, 0.76, 0.60213, 0.9, -0.01066, 0.9])
        ),
        "capetown": .init(
            assetName: "home_city_capetown",
            location: measured(.doorLintel, center: [0.3362, 0.14], size: [142, 70],
                          quad: [0.12122, 0.11, 0.53583, 0.145, 0.53583, 0.163, 0.12122, 0.128]),
            map: measured(.wall, center: [0.82247, 0.294], size: [110, 126],
                          quad: [0.683274, 0.1953897, 1, 0.1103183, 1, 0.3841932, 0.683274, 0.3918771]),
            story: measured(.wall, center: [0.77845, 0.49], size: [130, 132],
                          quad: [0.683274, 0.1953897, 1, 0.1103183, 1, 0.3841932, 0.683274, 0.3918771]),
            activities: measured(.floor, center: [0.32597, 0.79], size: [144, 90],
                          quad: [0.2491103, 0.7958288, 0.4128114, 0.7821076, 0.4614472, 0.8358946, 0.2787663, 0.8572997])
        ),
        "singapore": .init(
            assetName: "home_city_singapore",
            location: measured(.doorLintel, center: [0.28, 0.125], size: [142, 70],
                          quad: [0.01, 0.08, 0.54, 0.08, 0.54, 0.14, 0.01, 0.14]),
            map: measured(.wall, center: [0.806, 0.31], size: [132, 126],
                          quad: [0.6096131, 0.2190889, 1, 0.2190889, 1, 0.4007592, 0.6096131, 0.4007592]),
            story: measured(.wall, center: [0.79, 0.465], size: [140, 132],
                          quad: [0.6096131, 0.2190889, 1, 0.2190889, 1, 0.4007592, 0.6096131, 0.4007592]),
            activities: measured(.floor, center: [0.32, 0.8], size: [144, 90],
                          quad: [0.12, 0.78, 0.55, 0.78, 0.63, 0.9, 0.02, 0.9])
        ),
        "dublin": .init(
            assetName: "home_city_dublin",
            location: measured(.doorLintel, center: [0.21268, 0.273], size: [142, 70],
                          quad: [-0.01306, 0.245, 0.39431, 0.259, 0.39431, 0.29, -0.01306, 0.28]),
            map: measured(.wall, center: [0.8417, 0.35], size: [110, 126],
                          quad: [0.6745843, 0.2712795, 1, 0.2015376, 1, 0.4838001, 0.6817102, 0.4728171]),
            story: measured(.wall, center: [0.79758, 0.56], size: [134, 132],
                          quad: [0.6745843, 0.2712795, 1, 0.2015376, 1, 0.4838001, 0.6817102, 0.4728171]),
            activities: measured(.floor, center: [0.32556, 0.798], size: [144, 90],
                          quad: [0.2505938, 0.8215266, 0.5225653, 0.79352, 0.6484561, 0.8660077, 0.3254157, 0.9044481])
        ),
        "edinburgh": .init(
            assetName: "home_city_edinburgh",
            location: measured(.doorLintel, center: [0.725, 0.145], size: [142, 70],
                          quad: [0.46, 0.126, 0.98, 0.126, 0.98, 0.163, 0.46, 0.163]),
            map: measured(.wall, center: [0.183, 0.39], size: [110, 126],
                          quad: [0.0293083, 0.2548807, 0.3352872, 0.2548807, 0.3352872, 0.532538, 0.0293083, 0.532538]),
            story: measured(.wall, center: [0.196, 0.606], size: [132, 132],
                          quad: [0.0293083, 0.2548807, 0.3352872, 0.2548807, 0.3352872, 0.532538, 0.0293083, 0.532538]),
            activities: measured(.door, center: [0.725, 0.665], size: [144, 90],
                          quad: [0.5627198, 0.5878525, 0.901524, 0.5878525, 0.901524, 0.7250542, 0.5627198, 0.7250542])
        ),
        "vancouver": .init(
            assetName: "home_city_vancouver",
            location: measured(.doorLintel, center: [0.69963, 0.145], size: [142, 70],
                          quad: [0.405694, 0.1212287, 0.9786477, 0.1343939, 0.9786477, 0.1634668, 0.405694, 0.153593]),
            map: measured(.wall, center: [0.18265, 0.295], size: [128, 126],
                          quad: [0, 0.2051563, 0.3831554, 0.2106418, 0.3831554, 0.3872737, 0, 0.3878223]),
            story: measured(.wall, center: [0.198, 0.508], size: [142, 140],
                          quad: [0, 0.2051563, 0.3831554, 0.2106418, 0.3831554, 0.3872737, 0, 0.3878223]),
            activities: measured(.floor, center: [0.6638, 0.8], size: [144, 90],
                          quad: [0.5848161, 0.828305, 0.8102017, 0.8200768, 0.8303677, 0.8546352, 0.5895611, 0.8656061])
        ),
        "auckland": .init(
            assetName: "home_city_auckland",
            location: measured(.doorLintel, center: [0.2702, 0.212], size: [142, 70],
                          quad: [0.03019, 0.193, 0.51021, 0.2, 0.51021, 0.24, 0.03019, 0.234]),
            map: measured(.wall, center: [0.78597, 0.355], size: [140, 126],
                          quad: [0.5462085, 0.247807, 1, 0.2527412, 1, 0.4621711, 0.5473934, 0.4627193]),
            story: measured(.wall, center: [0.78597, 0.165], size: [140, 126],
                          quad: [0.5462085, 0.247807, 1, 0.2527412, 1, 0.4621711, 0.5473934, 0.4627193]),
            activities: measured(.floor, center: [0.29573, 0.799], size: [144, 90],
                          quad: [0.063981, 0.7379386, 0.4940758, 0.7291667, 0.5319905, 0.7883772, 0.0260664, 0.8037281])
        ),
        "nairobi": .init(
            assetName: "home_city_nairobi",
            location: measured(.doorLintel, center: [0.755, 0.20315], size: [142, 70],
                          quad: [0.5, 0.18307, 0.98, 0.18307, 0.98, 0.22423, 0.5, 0.22423]),
            map: measured(.wall, center: [0.25, 0.33163], size: [150, 126],
                          quad: [0, 0.2380435, 0.4876616, 0.2396739, 0.4876616, 0.4206522, 0, 0.4201087]),
            story: measured(.wall, center: [0.29, 0.51031], size: [148, 132],
                          quad: [0, 0.2380435, 0.4876616, 0.2396739, 0.4876616, 0.4206522, 0, 0.4201087]),
            activities: measured(.floor, center: [0.72, 0.81346], size: [144, 90],
                          quad: [0.52, 0.7703, 0.95, 0.7713, 1, 0.89778, 0.41, 0.89778])
        ),
        "toronto": .init(
            assetName: "home_city_toronto",
            location: measured(.doorLintel, center: [0.30504, 0.191], size: [142, 70],
                          quad: [0.0712589, 0.1762768, 0.5368171, 0.1707853, 0.5368171, 0.2075783, 0.0712589, 0.214168]),
            map: measured(.wall, center: [0.82836, 0.313], size: [112, 126],
                          quad: [0.6579572, 0.2235036, 1, 0.2185612, 1, 0.4102142, 0.6579572, 0.4091159]),
            story: measured(.wall, center: [0.80784, 0.488], size: [140, 132],
                          quad: [0.6579572, 0.2235036, 1, 0.2185612, 1, 0.4102142, 0.6579572, 0.4091159]),
            activities: measured(.door, center: [0.29477, 0.645], size: [144, 90],
                          quad: [0.1306413, 0.5634267, 0.4714964, 0.5705656, 0.4714964, 0.7018122, 0.1306413, 0.6908292])
        ),
        "sydney": .init(
            assetName: "home_city_sydney",
            location: measured(.doorLintel, center: [0.29, 0.21], size: [142, 70],
                          quad: [0.07, 0.194, 0.55, 0.195, 0.55, 0.231, 0.07, 0.23]),
            map: measured(.wall, center: [0.8, 0.355], size: [128, 126],
                          quad: [0.6084408, 0.2592191, 1, 0.2592191, 1, 0.4436009, 0.6084408, 0.4436009]),
            story: measured(.wall, center: [0.8, 0.168], size: [140, 140],
                          quad: [0.6084408, 0.2592191, 1, 0.2592191, 1, 0.4436009, 0.6084408, 0.4436009]),
            activities: measured(.floor, center: [0.34, 0.802], size: [144, 90],
                          quad: [0.14, 0.77, 0.57, 0.77, 0.66, 0.9, 0.03, 0.9])
        ),
        "neworleans": .init(
            assetName: "home_city_neworleans",
            location: measured(.doorLintel, center: [0.725, 0.15926], size: [142, 70],
                          quad: [0.468, 0.14623, 0.98, 0.14623, 0.98, 0.16828, 0.468, 0.16828]),
            map: measured(.wall, center: [0.186, 0.34967], size: [120, 126],
                          quad: [0, 0.2589577, 0.3450704, 0.2589577, 0.3438967, 0.4435396, 0, 0.4435396]),
            story: measured(.wall, center: [0.215, 0.51002], size: [142, 132],
                          quad: [0, 0.2589577, 0.3450704, 0.2589577, 0.3438967, 0.4435396, 0, 0.4435396]),
            activities: measured(.floor, center: [0.64, 0.80266], size: [144, 90],
                          quad: [0.43, 0.7746, 0.86, 0.7746, 0.96, 0.89987, 0.33, 0.89987])
        ),
        "manchester": .init(
            assetName: "home_city_manchester",
            location: measured(.doorLintel, center: [0.338, 0.165], size: [142, 70],
                          quad: [0.12, 0.151, 0.548, 0.156, 0.548, 0.181, 0.12, 0.176]),
            map: measured(.wall, center: [0.836, 0.264], size: [112, 126],
                          quad: [0.6658851, 0.1534707, 1, 0.0927332, 1, 0.356833, 0.6658851, 0.3633406]),
            story: measured(.wall, center: [0.79, 0.476], size: [140, 140],
                          quad: [0.6658851, 0.1534707, 1, 0.0927332, 1, 0.356833, 0.6658851, 0.3633406]),
            activities: measured(.floor, center: [0.34, 0.81], size: [144, 90],
                          quad: [0.14, 0.77, 0.57, 0.77, 0.68, 0.9, 0.02, 0.9])
        ),
        "kingston": .init(
            assetName: "home_city_kingston",
            location: measured(.doorLintel, center: [0.755, 0.19], size: [142, 70],
                          quad: [0.53, 0.187, 0.963, 0.167, 0.963, 0.204, 0.53, 0.224]),
            map: measured(.wall, center: [0.18, 0.309], size: [112, 126],
                          quad: [0, 0.1464208, 0.3458382, 0.2207158, 0.3458382, 0.4403471, 0, 0.4544469]),
            story: measured(.wall, center: [0.23, 0.52], size: [140, 132],
                          quad: [0, 0.1464208, 0.3458382, 0.2207158, 0.3458382, 0.4403471, 0, 0.4544469]),
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

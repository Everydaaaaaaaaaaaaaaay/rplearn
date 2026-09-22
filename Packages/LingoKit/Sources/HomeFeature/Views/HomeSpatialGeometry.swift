import SwiftUI
import DesignSystem

/// 按当前十五张城市母版标定门内远景范围；不是相机测距，也不重建遮挡背面。
struct HomeSpatialGeometry {
    private let calibration: Calibration
    var opening: CGRect { calibration.normalizedContours[0].reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) } }

    init(assetName: String) {
        let city = assetName.replacingOccurrences(of: "home_city_", with: "")
        calibration = Self.calibrations[city] ?? Self.calibrations["london"]!
    }

    struct Calibration {
        let sourceSize: CGSize
        let apertures: [[CGPoint]]

        init(_ width: CGFloat, _ height: CGFloat, _ polygons: [[(CGFloat, CGFloat)]]) {
            sourceSize = CGSize(width: width, height: height)
            apertures = polygons.map { $0.map { CGPoint(x: $0.0, y: $0.1) } }
        }

        var normalizedContours: [[CGPoint]] {
            apertures.map { $0.map { CGPoint(x: $0.x / sourceSize.width, y: $0.y / sourceSize.height) } }
        }
    }

    // 逐张原图像素标定完整玻璃开口，门廊、台阶、门外花盆不属于门框。
    // 每个门把手有独立凹口；都柏林上窗按玻璃分片，保留窗棂。
    static let calibrations: [String: Calibration] = [
        "auckland": .init(852, 1842, [
            [(127,427),(363,427),(363,827),(346,827),(346,845),(363,845),(363,1095),(127,1095)],
        ]),
        "capetown": .init(851, 1840, [
            [(92,373),(371,373),(371,857),(346,857),(346,877),(371,877),(371,1213),(92,1213)],
        ]),
        "dublin": .init(850, 1838, [
            [(103,465),(335,465),(335,816),(322,816),(322,833),(335,833),(335,1056),(103,1056)],
            [(78,392),(82,374),(90,356),(103,337),(187,386),(184,392)],
            [(112,330),(136,310),(156,301),(196,367),(191,375)],
            [(168,295),(185,289),(204,286),(214,285),(214,363),(203,364)],
            [(226,285),(249,287),(270,294),(239,365),(226,362)],
            [(281,301),(305,314),(328,334),(249,378),(244,370)],
            [(338,344),(351,366),(360,392),(259,392),(255,384)],
            [(192,394),(197,384),(208,377),(220,375),(234,378),(246,386),(249,394)],
        ]),
        "edinburgh": .init(853, 1844, [
            [(97,316),(375,316),(375,809),(358,809),(358,831),(375,831),(375,1144),(97,1144)],
        ]),
        "kingston": .init(852, 1842, [
            [(99,386),(347,386),(347,815),(338,815),(338,836),(347,836),(347,1075),(99,1075)],
        ]),
        "london": .init(853, 1844, [
            [(112,359),(381,359),(381,868),(362,868),(362,886),(381,886),(381,1215),(112,1215),(112,1152),(114,1165),(112,1138),(124,1138),(126,1128),(122,1110),(112,1090),(112,1080),(127,1110),(129,1102),(121,1070),(112,1057),(112,1042),(121,1058),(124,1060),(122,1050),(115,1038),(112,1037)],
        ]),
        "manchester": .init(853, 1844, [
            [(94,347),(366,347),(366,847),(347,847),(347,866),(366,866),(366,1109),(94,1109)],
        ]),
        "melbourne": .init(829, 1792, [
            [(83,310),(336,310),(336,1022),(83,1022),(83,815),(103,815),(103,795),(83,795)],
        ]),
        "nairobi": .init(853, 1844, [
            [(106,378),(374,378),(374,789),(347,789),(347,807),(374,807),(374,1124),(106,1124)],
        ]),
        "neworleans": .init(853, 1844, [
            [(91,453),(359,453),(359,910),(331,910),(331,927),(359,927),(359,1181),(91,1181)],
        ]),
        "newyork": .init(829, 1792, [
            [(89,329),(345,329),(345,810),(336,810),(336,824),(345,824),(345,1050),(89,1050)],
        ]),
        "singapore": .init(852, 1842, [
            [(90,311),(376,311),(376,825),(347,825),(347,847),(376,847),(376,1169),(90,1169)],
        ]),
        "sydney": .init(853, 1844, [
            [(115,438),(366,438),(366,1166),(115,1166),(115,893),(130,893),(130,878),(115,878)],
        ]),
        "toronto": .init(853, 1844, [
            [(85,305),(376,312),(376,1066),(85,1072),(85,836),(103,836),(103,818),(85,818)],
        ]),
        "vancouver": .init(851, 1840, [
            [(111,478),(366,478),(366,892),(346,892),(346,909),(366,909),(366,1184),(111,1184)],
        ]),
    ]

    static let foregroundDepth: CGFloat = 0.16
    static let backgroundDepth: CGFloat = 0.03

    var layers: [DSSceneParallaxLayer] {
        let apertures = calibration.normalizedContours
        return [DSSceneParallaxLayer(contour: apertures[0], depth: Self.foregroundDepth,
                                    inverted: true, additionalContours: Array(apertures.dropFirst()))]
    }

    func depth(at point: CGPoint) -> CGFloat {
        layers[0].contains(point) ? Self.foregroundDepth : Self.backgroundDepth
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

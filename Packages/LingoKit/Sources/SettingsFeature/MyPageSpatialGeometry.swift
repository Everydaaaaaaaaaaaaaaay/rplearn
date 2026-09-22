import SwiftUI
import DesignSystem

/// 人工标定的相对深度，不代表照片包含真实测距数据。静止时严格还原原图。
enum MyPageSpatialGeometry {
    static let size = CGSize(width: TravelDeskLayout.canvasWidth, height: TravelDeskLayout.canvasHeight)
    static let cameraLimit: CGFloat = 32

    static let backgroundDepth: CGFloat = 0.08

    /// 母版物件的外轮廓，包含紧贴物件的原有接触阴影；每个物件只有一个移动速度。
    static let layers: [DSSceneParallaxLayer] = [
        layer(0.21, shadowRight: 12, [(5,242),(281,187),(293,196),(329,440),(317,453),(46,482),(32,466)]),
        layer(0.39, shadowBottom: 6, [(359,340),(406,341),(414,348),(549,357),(558,370),(549,509),(532,516),(331,493),(326,475),(340,365),(347,354)]),
        layer(0.27, [(634,265),(651,269),(790,309),(802,323),(793,417),(777,446),(797,459),(811,475),(805,486),(789,485),(765,457),(740,458),(588,411),(581,398),(615,281)]),
        layer(0.21, [(294,712),(533,714),(551,730),(551,1134),(537,1156),(285,1154),(268,1136),(271,732)]),
        layer(0.29, [(22,1291),(231,1248),(249,1253),(318,1606),(304,1626),(116,1665),(124,1690),(108,1702),(91,1669),(79,1639)]),
        layer(0.22, [(365,1352),(475,1352),(493,1367),(495,1648),(483,1672),(358,1674),(342,1660),(344,1374)]),
        layer(0.25, shadowRight: 10, [(646,1263),(670,1267),(692,1288),(693,1310),(662,1442),(669,1461),(657,1546),(640,1574),(584,1776),(566,1799),(538,1801),(520,1785),(523,1753),(566,1574),(564,1550),(578,1473),(590,1451),(623,1324),(621,1304),(632,1284)]),
        layer(0.35, [(699,1488),(732,1498),(764,1518),(775,1543),(764,1588),(745,1610),(715,1606),(681,1589),(670,1567),(680,1516)]),
    ]

    private static func layer(_ depth: CGFloat, shadowBottom: CGFloat = 30, shadowRight: CGFloat = 22, _ points: [(CGFloat, CGFloat)]) -> DSSceneParallaxLayer {
        // 把抗锯齿和取样接缝放到物件外侧的背景中，扩大接触阴影的覆盖范围。
        // 下方与右侧保留更多投影，避免同一阴影一半随物件移动、一半留在底图。
        // 相机底部紧邻地图；护照和手表右侧紧邻其他物件，分别限制扩张。
        let coordinates: [CGPoint] = points.map { point in CGPoint(x: point.0, y: point.1) }
        let sorted: [CGPoint] = coordinates.sorted { a, b in
            if a.x == b.x { return a.y < b.y }
            return a.x < b.x
        }
        func cross(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
            (b.x-a.x)*(c.y-a.y) - (b.y-a.y)*(c.x-a.x)
        }
        func half(_ points: [CGPoint]) -> [CGPoint] {
            var result: [CGPoint] = []
            for point in points {
                while result.count >= 2 && cross(result[result.count-2], result[result.count-1], point) <= 0 { result.removeLast() }
                result.append(point)
            }
            return Array(result.dropLast())
        }
        let hull = half(sorted) + half(Array(sorted.reversed()))
        let expanded = hull.indices.map { index -> CGPoint in
            let previous = hull[(index + hull.count - 1) % hull.count]
            let current = hull[index]
            let next = hull[(index + 1) % hull.count]
            func normal(_ a: CGPoint, _ b: CGPoint) -> CGVector {
                let length = hypot(b.x-a.x, b.y-a.y)
                return CGVector(dx: (b.y-a.y)/length, dy: -(b.x-a.x)/length)
            }
            let a = normal(previous, current), b = normal(current, next)
            let denominator = max(0.25, 1 + a.dx*b.dx + a.dy*b.dy)
            let nx = (a.dx + b.dx) / denominator
            let ny = (a.dy + b.dy) / denominator
            let horizontalMargin: CGFloat = nx > 0 ? shadowRight : 10
            let verticalMargin: CGFloat = ny > 0 ? shadowBottom : 10
            return CGPoint(x: (current.x + nx * horizontalMargin)/825,
                           y: (current.y + ny * verticalMargin)/1906)
        }
        // 只开放微小的遮挡差，避免单张照片中的接触阴影与新视点明显分离。
        let parallaxDepth = backgroundDepth + (depth - backgroundDepth) * 0.6
        return DSSceneParallaxLayer(contour: expanded, depth: parallaxDepth)
    }

    static func depth(at point: CGPoint) -> CGFloat {
        layers.last(where: { $0.contains(point) })?.depth ?? backgroundDepth
    }

    static func displacement(at point: UnitPoint, camera: CGSize, floating: Bool = false) -> CGSize {
        let depth = depth(at: CGPoint(x: point.x, y: point.y)) + (floating ? 0.025 : 0)
        return CGSize(width: camera.width * depth, height: camera.height * depth)
    }

    static func resisted(_ translation: CGSize) -> CGSize {
        DSSceneCameraResistance.resisted(translation)
    }

    static func unresisted(_ camera: CGSize) -> CGSize {
        DSSceneCameraResistance.unresisted(camera)
    }

    static func coverageScale(camera: CGSize) -> CGFloat {
        // 原图边缘用同源背景承接；整体覆盖补偿同步作用于入口和命中区域。
        1 + max(abs(camera.width) * 0.12 / size.width, abs(camera.height) * 0.12 / size.height) * 2
    }
}

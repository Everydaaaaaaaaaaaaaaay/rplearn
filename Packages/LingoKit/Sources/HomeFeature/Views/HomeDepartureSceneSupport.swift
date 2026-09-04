import SwiftUI

/// 首页摄影母版与所有 SceneKit 节点共享同一坐标系。
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

/// SceneKit 中承载入口的真实局部平面。
///
/// X/Y 旋转产生由相机投影得到的梯形透视，不再使用二维仿射近似；lift 则决定
/// 核心内容与摄影物件表面之间的空间距离。
struct HomeScenePlane: Sendable {
    let rotationX: Double
    let rotationY: Double
    let rotationZ: Double
    let lift: CGFloat
    let scaleX: CGFloat
    let scaleY: CGFloat
    let shadowOffset: CGSize
    let shadowDepth: CGFloat
    let glowBias: CGFloat
    let shadowBias: CGFloat
}

struct HomeDepartureHotspotLayout: Sendable {
    let center: UnitPoint
    let hitSize: CGSize
    let renderSize: CGSize
    let plane: HomeScenePlane
}

struct HomeDepartureSceneLayout: Sendable {
    let assetName: String
    let location: HomeDepartureHotspotLayout
    let map: HomeDepartureHotspotLayout
    let story: HomeDepartureHotspotLayout
    let activities: HomeDepartureHotspotLayout

    /// 坐标按 853 × 1844 的一次性生产底图逐入口测量。
    /// 角度来自各承载物自身的消失线：墙面入口保持克制，地面入口采用明显俯视。
    static let production = HomeDepartureSceneLayout(
        assetName: "home_departure_foyer",
        location: .init(
            center: UnitPoint(x: 0.215, y: 0.12),
            hitSize: CGSize(width: 142, height: 82),
            renderSize: CGSize(width: 142, height: 82),
            plane: HomeScenePlane(
                rotationX: -2.5,
                rotationY: 12,
                rotationZ: -6,
                lift: 8,
                scaleX: 1,
                scaleY: 0.99,
                shadowOffset: CGSize(width: 2, height: 6),
                shadowDepth: 7,
                glowBias: 0.72,
                shadowBias: 0.66
            )
        ),
        map: .init(
            center: UnitPoint(x: 0.68, y: 0.19),
            hitSize: CGSize(width: 132, height: 126),
            renderSize: CGSize(width: 140, height: 132),
            plane: HomeScenePlane(
                rotationX: -3,
                rotationY: -18,
                rotationZ: 5,
                lift: 11,
                scaleX: 1,
                scaleY: 0.99,
                shadowOffset: CGSize(width: -3, height: 7),
                shadowDepth: 10,
                glowBias: 0.78,
                shadowBias: 0.82
            )
        ),
        story: .init(
            center: UnitPoint(x: 0.62, y: 0.49),
            hitSize: CGSize(width: 146, height: 132),
            renderSize: CGSize(width: 154, height: 140),
            plane: HomeScenePlane(
                rotationX: -5,
                rotationY: -14,
                rotationZ: 1.5,
                lift: 13,
                scaleX: 1,
                scaleY: 0.985,
                shadowOffset: CGSize(width: -2, height: 9),
                shadowDepth: 12,
                glowBias: 0.92,
                shadowBias: 0.72
            )
        ),
        activities: .init(
            center: UnitPoint(x: 0.25, y: 0.70),
            hitSize: CGSize(width: 148, height: 126),
            // 地面平面投影后会产生显著纵向缩短，因此渲染平面比命中区更高。
            renderSize: CGSize(width: 158, height: 168),
            plane: HomeScenePlane(
                rotationX: -38,
                rotationY: 4,
                rotationZ: 6,
                lift: 15,
                scaleX: 1,
                scaleY: 1,
                shadowOffset: CGSize(width: 5, height: 10),
                shadowDepth: 14,
                glowBias: 1.12,
                shadowBias: 0.42
            )
        )
    )
}

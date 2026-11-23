import SwiftUI

/// 一座城市的卡通全景配方：地形、地标、植物和运动元素。
struct PuffCityRecipe: Sendable {
    enum Terrain: Sendable {
        /// 河流或港湾横穿画面，地标立在远岸。
        case water
        /// 平地城市。
        case land
    }

    /// 由远到近的图层；静态层只在时段变化时重画，Motion 层逐帧画。
    enum Layer: Sendable {
        /// 天空、日月、远景与远景上的薄雾。
        case back
        /// 星星、云、飞鸟。
        case backMotion
        /// 水面（含地标倒影）或远处地面。
        case terrain
        /// 远岸地标，单独成层以便投下柔和的影子。
        case landmarks
        /// 水面亮片、船、摩天轮、钟针。
        case farMotion
        /// 近岸草边、道路、树和街道小物。
        case near
        /// 道路上的车。
        case nearMotion
    }

    typealias Drawing = @Sendable (PuffScenePainter) -> Void

    let id: String
    let nameZh: String
    let timeZoneID: String
    let terrain: Terrain
    /// 太阳或月亮在全景中的横向位置。
    let celestialX: CGFloat
    /// 远山、远景楼群：位于云层之后。
    let backdrop: Drawing
    /// 地标：位于地形之上。
    let landmarks: Drawing
    /// 近岸的树、电话亭、路灯。
    let foreground: Drawing
    /// 逐帧运动的元素：摩天轮、车、船、钟表指针。
    let movers: Drawing
    /// 做小图标时的取景中心：城市最有辨识度的地标。
    var iconX: CGFloat = 190

    func clock(at date: Date) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneID) ?? .current
        return calendar.dateComponents([.hour, .minute], from: date)
    }

    func draw(_ layer: Layer, painter: PuffScenePainter, skyTop: CGFloat) {
        switch layer {
        case .back:
            painter.sky(extendingAbove: skyTop)
            painter.celestial(x: celestialX)
            backdrop(painter)
            painter.horizonHaze()
        case .backMotion:
            painter.stars()
            painter.clouds(seed: id.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) })
            painter.birds()
        case .terrain:
            switch terrain {
            case .water:
                painter.water()
                reflection(painter)
            case .land:
                painter.farGround()
            }
        case .landmarks:
            landmarks(painter)
        case .farMotion:
            if terrain == .water { painter.waterSparkles() }
            var far = painter
            far.moverPass = .far
            movers(far)
        case .near:
            painter.nearBank()
            foreground(painter)
        case .nearMotion:
            var near = painter
            near.moverPass = .near
            movers(near)
        }
    }

    /// 远岸与地标在水里的倒影：以岸线为轴翻转，越往近处越淡，交给涟漪着色器晃动。
    private func reflection(_ painter: PuffScenePainter) {
        let top = PuffScenePainter.horizon
        let bottom: CGFloat = 157
        var context = painter.ctx
        context.clip(to: Path(CGRect(x: -40, y: top + 1.6, width: PuffScenePainter.width + 80, height: bottom - top)))
        var mirrored = context
        mirrored.translateBy(x: 0, y: top * 2 + 1)
        mirrored.scaleBy(x: 1, y: -1)
        mirrored.opacity = 0.34
        let mirror = PuffScenePainter(ctx: mirrored, mood: painter.mood, time: 0, clock: painter.clock)
        backdrop(mirror)
        landmarks(mirror)
        let water = painter.atmosphere.water.color
        context.fill(
            Path(CGRect(x: -40, y: top, width: PuffScenePainter.width + 80, height: bottom - top)),
            with: .linearGradient(
                Gradient(colors: [water.opacity(0.15), water.opacity(0.85)]),
                startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: bottom)
            )
        )
    }
}

/// 支持城市的配方表。新增城市时只需追加一项配方。
enum PuffCityCatalog {
    static func recipe(for regionID: String?) -> PuffCityRecipe {
        let normalized = regionID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return recipes[normalized] ?? london
    }

    static let recipes: [String: PuffCityRecipe] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.id, $0) }
    )

    static var all: [PuffCityRecipe] {
        [london, manchester, edinburgh, dublin, newYork, newOrleans, toronto, vancouver,
         sydney, melbourne, auckland, singapore, capeTown, nairobi, kingston]
    }

    /// 只读城市中文名，供页面文案使用。
    static func nameZh(for regionID: String?) -> String { recipe(for: regionID).nameZh }

    static let london = PuffCityRecipe(
        id: "london", nameZh: "伦敦", timeZoneID: "Europe/London", terrain: .water, celestialX: 318,
        backdrop: { p in
            p.farSkyline(seed: 11, skip: [384...470, 668...710])
            p.stPauls(408)
            p.gherkin(456)
            p.shard(690)
        },
        landmarks: { p in
            p.parliament(from: 6, to: 150)
            p.bigBen(168)
            p.towerBridge(560)
        },
        foreground: { p in
            p.roundTree(26, size: 1.15)
            p.roundTree(118)
            p.lampPost(200)
            p.phoneBox(326)
            p.roundTree(352, size: 0.9)
            p.lampPost(430)
            p.roundTree(470, size: 0.95)
            p.roundTree(694, size: 1.15)
        },
        movers: { p in
            p.ferrisWheel(262, centerY: 86, radius: 44)
            p.bigBenHands(168)
            p.sail(.ferry(0xFF7A8A), range: 330...470, period: 46)
            p.drive(.doubleDecker, period: 28)
        }
    )
}

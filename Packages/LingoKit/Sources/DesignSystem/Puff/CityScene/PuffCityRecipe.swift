import SwiftUI

/// 一座城市的卡通全景配方：地形、地标、植物和运动元素。
struct PuffCityRecipe: Sendable {
    enum Terrain: Sendable {
        /// 河流或港湾横穿画面，地标立在远岸。
        case water
        /// 平地城市。
        case land
    }

    enum Layer: Sendable {
        case back
        case backMotion
        case front
        case frontMotion
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
        case .backMotion:
            painter.stars()
            painter.clouds(seed: id.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) })
            painter.birds()
        case .front:
            switch terrain {
            case .water: painter.water()
            case .land: painter.farGround()
            }
            landmarks(painter)
            painter.nearBank()
            foreground(painter)
        case .frontMotion:
            if terrain == .water { painter.waterSparkles() }
            movers(painter)
        }
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

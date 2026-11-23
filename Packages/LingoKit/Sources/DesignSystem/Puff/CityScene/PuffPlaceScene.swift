import SwiftUI

/// 城市活动地点的竖版场景，按城市当地时间切换昼夜。
///
/// 有风格化实拍（`PuffPlacePhoto`）的地点显示活照片：手绘天空在后，树叶、水面会动，镜头缓慢漂移；
/// 其余地点（如约会地点）画卡通场景：远处是所在城市的卡通天际线，近处是地点本身。
public struct PuffPlaceScene: View {
    /// 地点类型，与活动目录的 category 一致；未知类型按街道绘制。
    public enum Kind: String, Sendable, CaseIterable {
        case street, market, park, community, bookshop, transport, cafe

        public init(category: String) {
            self = Kind(rawValue: category) ?? .street
        }
    }

    private let regionID: String?
    private let kind: Kind
    private let placeID: String
    private let seed: Int
    private let moodOverride: PuffSceneMood?
    private let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isOnScreen = false

    /// - Parameters:
    ///   - placeID: 地点 ID：有风格化实拍时据此找照片；卡通场景用它做配色种子，同一地点每次画得一样。
    public init(regionID: String?, kind: Kind, placeID: String, mood: PuffSceneMood? = nil, isActive: Bool = true) {
        self.regionID = regionID
        self.kind = kind
        self.placeID = placeID
        self.seed = placeID.unicodeScalars.reduce(7) { ($0 &* 31) &+ Int($1.value) }
        self.moodOverride = mood
        self.isActive = isActive
    }

    public var body: some View {
        let recipe = PuffCityCatalog.recipe(for: regionID)
        TimelineView(.everyMinute) { context in
            let clock = recipe.clock(at: context.date)
            let mood = moodOverride ?? PuffSceneMood.at(hour: clock.hour ?? 12)
            let isPaused = reduceMotion || !isActive || !isOnScreen || scenePhase != .active
            if Self.hasPhoto(placeID: placeID) {
                PuffPlacePhotoScene(placeID: placeID, kind: kind, seed: seed, mood: mood, clock: clock, isPaused: isPaused)
            } else {
                PuffPlaceSceneCanvas(recipe: recipe, kind: kind, seed: seed, mood: mood, clock: clock, isPaused: isPaused)
            }
        }
        .onAppear { isOnScreen = true }
        .onDisappear { isOnScreen = false }
        .accessibilityHidden(true)
    }
}

public extension PuffPlaceScene {
    /// 该地点有风格化实拍，页面可据此提供“照片信息”。
    static func hasPhoto(placeID: String) -> Bool {
        PuffPlacePhotoLibrary.url(for: placeID) != nil
    }
}

struct PuffPlaceSceneCanvas: View {
    let recipe: PuffCityRecipe
    let kind: PuffPlaceScene.Kind
    let seed: Int
    let mood: PuffSceneMood
    let clock: DateComponents
    let isPaused: Bool
    var fixedTime: TimeInterval?

    /// 竖版设计宽度；高度随屏幕变化，地面线位于 60% 处。
    static let width: CGFloat = 390
    static let foregroundScale: CGFloat = 1.15

    enum Layer { case back, backMotion, front, frontMotion }

    var body: some View {
        ZStack {
            staticLayer(.back)
            animated(.backMotion)
            staticLayer(.front)
            animated(.frontMotion)
        }
    }

    private struct StaticKey: Equatable {
        let recipeID: String
        let kind: PuffPlaceScene.Kind
        let seed: Int
        let layer: Layer
        let mood: PuffSceneMood
        let clock: DateComponents
    }

    /// 静态层与暂停状态无关，只在地点、时段或当地时间变化时在后台重画，见 `PuffStaticCanvas`。
    @ViewBuilder
    private func staticLayer(_ layer: Layer) -> some View {
        if let fixedTime {
            Canvas { context, size in draw(layer, context, size, time: fixedTime) }
        } else {
            PuffStaticCanvas(key: StaticKey(recipeID: recipe.id, kind: kind, seed: seed, layer: layer, mood: mood, clock: clock)) { context, size in
                draw(layer, context, size, time: 0)
            }
            .equatable()
        }
    }

    @ViewBuilder
    private func animated(_ layer: Layer) -> some View {
        if let fixedTime {
            Canvas { context, size in draw(layer, context, size, time: fixedTime) }
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: isPaused)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 21_600)
                Canvas(rendersAsynchronously: true) { context, size in
                    draw(layer, context, size, time: time)
                }
            }
        }
    }

    private func draw(_ layer: Layer, _ context: GraphicsContext, _ size: CGSize, time: TimeInterval) {
        guard size.width > 0, size.height > 0 else { return }
        let scale = size.width / Self.width
        let height = size.height / scale
        var context = context
        context.scaleBy(x: scale, y: scale)
        let painter = PuffScenePainter(ctx: context, mood: mood, time: time, clock: clock)
        let stage = PuffPlaceStage(painter: painter, kind: kind, seed: seed, height: height)
        switch layer {
        case .back:
            stage.sky()
            stage.distantCity(recipe)
        case .backMotion:
            painter.stars()
            stage.clouds()
        case .front, .frontMotion:
            // 近景以地面中点为锚放大，让地点在竖屏里更饱满。
            var near = context
            near.translateBy(x: Self.width / 2, y: stage.ground)
            near.scaleBy(x: Self.foregroundScale, y: Self.foregroundScale)
            near.translateBy(x: -Self.width / 2, y: -stage.ground)
            let nearStage = PuffPlaceStage(
                painter: PuffScenePainter(ctx: near, mood: mood, time: time, clock: clock),
                kind: kind, seed: seed, height: height
            )
            if layer == .front { nearStage.place() } else { nearStage.movers() }
        }
    }
}

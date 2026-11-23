import SwiftUI

/// 程序化绘制的卡通城市全景。替代页面里的城市实拍：
/// 按城市当地时间切换白天、黄昏、夜晚；云、鸟、摩天轮、车船会缓慢运动。
///
/// 全景宽 720 个设计单位，`viewport` 选择看哪一半，让不同页面看到同一座城市的不同角度。
public struct PuffCityScene: View {
    public enum Viewport: Sendable, Equatable {
        case west
        case center
        case east
        case full
        /// 以全景中某个横坐标为中心、宽 360 单位的取景。
        case focus(CGFloat)

        var range: ClosedRange<CGFloat> {
            switch self {
            case .west: 0...360
            case .center: 150...510
            case .east: 360...720
            case .full: 0...720
            case .focus(let x): (x - 180)...(x + 180)
            }
        }
    }

    private let regionID: String?
    private let viewport: Viewport
    private let moodOverride: PuffSceneMood?
    private let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isOnScreen = false

    /// - Parameters:
    ///   - regionID: 旅程地区 ID，未知地区回退到伦敦。
    ///   - isActive: 页面不可见时传 false，停止逐帧动画以节省电量。
    public init(
        regionID: String?,
        viewport: Viewport = .west,
        mood: PuffSceneMood? = nil,
        isActive: Bool = true
    ) {
        self.regionID = regionID
        self.viewport = viewport
        self.moodOverride = mood
        self.isActive = isActive
    }

    public var body: some View {
        let recipe = PuffCityCatalog.recipe(for: regionID)
        TimelineView(.everyMinute) { context in
            let clock = recipe.clock(at: context.date)
            PuffCitySceneCanvas(
                recipe: recipe,
                mood: moodOverride ?? PuffSceneMood.at(hour: clock.hour ?? 12),
                clock: clock,
                viewport: viewport,
                isPaused: reduceMotion || !isActive || !isOnScreen || scenePhase != .active
            )
        }
        .onAppear { isOnScreen = true }
        .onDisappear { isOnScreen = false }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("卡通\(recipe.nameZh)街景")
        .accessibilityAddTraits(.isImage)
    }
}

/// 由远到近分层绘制：静态层只在尺寸或时段变化时重绘，逐帧层只画会动的元素。
/// 水面倒影交给涟漪着色器晃动，远岸地标投下柔和的影子，最上面罩一层日光。
struct PuffCitySceneCanvas: View {
    let recipe: PuffCityRecipe
    let mood: PuffSceneMood
    let clock: DateComponents
    let viewport: PuffCityScene.Viewport
    let isPaused: Bool
    /// 渲染工具与截图使用固定时间；为 nil 时跟随系统时钟。
    var fixedTime: TimeInterval?

    private static let shaders = ShaderLibrary.bundle(.module)

    var body: some View {
        GeometryReader { proxy in
            let unit = Self.visibleFrame(for: proxy.size, viewport: viewport).scale
            ZStack {
                staticLayer(.back)
                animatedLayer(.backMotion)
                if recipe.terrain == .water {
                    rippling(unit: unit)
                } else {
                    staticLayer(.terrain)
                }
                staticLayer(.landmarks)
                    .colorEffect(
                        Self.shaders.puffLandmarkLight(
                            .float(Float(PuffScenePainter.horizon * unit + proxy.size.height - PuffScenePainter.height * unit)),
                            .float(Float(unit))
                        ),
                        isEnabled: fixedTime == nil
                    )
                    .shadow(color: landmarkShadow, radius: unit * 1.2, x: unit * 2, y: unit * 0.6)
                animatedLayer(.farMotion)
                staticLayer(.near)
                animatedLayer(.nearMotion)
                sunlight(size: proxy.size, unit: unit)
            }
        }
    }

    private var landmarkShadow: Color {
        switch mood {
        case .day: Color(red: 0.32, green: 0.38, blue: 0.6).opacity(0.34)
        case .dusk: Color(red: 0.36, green: 0.27, blue: 0.5).opacity(0.38)
        case .night: Color(red: 0.05, green: 0.07, blue: 0.2).opacity(0.4)
        }
    }

    /// 倒影随水波左右轻晃。
    @ViewBuilder
    private func rippling(unit: CGFloat) -> some View {
        if fixedTime != nil {
            staticLayer(.terrain)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: isPaused)) { timeline in
                // 着色器按 600 秒一圈无缝循环。
                let time = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 600)
                staticLayer(.terrain)
                    .distortionEffect(
                        Self.shaders.puffRipple(.float(Float(time)), .float(Float(unit))),
                        maxSampleOffset: CGSize(width: unit * 2, height: 0)
                    )
            }
        }
    }

    /// 太阳一侧的暖光：屏幕混合，越远越淡。夜里不加。
    @ViewBuilder
    private func sunlight(size: CGSize, unit: CGFloat) -> some View {
        if mood != .night {
            let frame = Self.visibleFrame(for: size, viewport: viewport)
            let offsetY = size.height - PuffScenePainter.height * unit
            let center = UnitPoint(
                x: (recipe.celestialX - frame.minX) * unit / max(size.width, 1),
                y: ((mood == .day ? 40 : 104) * unit + offsetY) / max(size.height, 1)
            )
            RadialGradient(
                colors: [Color(red: 1, green: mood == .day ? 0.93 : 0.78, blue: mood == .day ? 0.74 : 0.6).opacity(0.32), .clear],
                center: center, startRadius: 0, endRadius: 300 * unit
            )
            .blendMode(.screen)
            .allowsHitTesting(false)
        }
    }

    private struct StaticKey: Equatable {
        let recipeID: String
        let layer: PuffCityRecipe.Layer
        let mood: PuffSceneMood
        let clock: DateComponents
        let viewport: PuffCityScene.Viewport
    }

    @ViewBuilder
    private func staticLayer(_ layer: PuffCityRecipe.Layer) -> some View {
        if let fixedTime {
            Canvas { context, size in draw(layer, context, size, time: fixedTime) }
        } else {
            PuffStaticCanvas(key: StaticKey(recipeID: recipe.id, layer: layer, mood: mood, clock: clock, viewport: viewport)) { context, size in
                draw(layer, context, size, time: 0)
            }
            .equatable()
        }
    }

    @ViewBuilder
    private func animatedLayer(_ layer: PuffCityRecipe.Layer) -> some View {
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

    private func draw(_ layer: PuffCityRecipe.Layer, _ context: GraphicsContext, _ size: CGSize, time: TimeInterval) {
        guard size.width > 0, size.height > 0 else { return }
        let frame = Self.visibleFrame(for: size, viewport: viewport)
        let scale = frame.scale
        let offsetY = size.height - PuffScenePainter.height * scale
        var context = context
        context.translateBy(x: -frame.minX * scale, y: offsetY)
        context.scaleBy(x: scale, y: scale)
        let painter = PuffScenePainter(ctx: context, mood: mood, time: time, clock: clock)
        recipe.draw(layer, painter: painter, skyTop: min(0, -offsetY / scale))
    }

    /// 矮卡片不裁掉高耸的地标：按高度缩放，再向两侧多露出一些全景。
    static func visibleFrame(for size: CGSize, viewport: PuffCityScene.Viewport) -> (minX: CGFloat, scale: CGFloat) {
        let range = viewport.range
        let rangeWidth = range.upperBound - range.lowerBound
        let scale = min(size.width / rangeWidth, size.height / requiredHeight)
        let visibleWidth = size.width / scale
        let center = (range.lowerBound + range.upperBound) / 2
        if case .focus = viewport {
            // 指定中心的取景不贴边，天空和地面本身向两侧多画了一截。
            return (center - visibleWidth / 2, scale)
        }
        let maxStart = max(PuffScenePainter.width - visibleWidth, 0)
        let start = min(max(center - visibleWidth / 2, 0), maxStart)
        return (start, scale)
    }

    /// 最高的地标顶到全景顶部约 4 个单位，保证尖顶完整。
    private static let requiredHeight: CGFloat = 176
}

/// 只在 `key` 变化时重画、并在后台线程绘制的静态画布。
///
/// 场景的暂停状态会在页面出现、离开、切到后台时变化，若静态层跟着重画，整幅全景就会在推入、返回、
/// 切换标签的那一帧同步画在主线程上，让按钮反馈和转场掉帧。静态层只取决于 `key`，用 `.equatable()`
/// 挡住无关更新；绘制放到后台线程，首次出现最多晚一帧。
struct PuffStaticCanvas<Key: Equatable & Sendable>: View, Equatable {
    let key: Key
    let draw: (GraphicsContext, CGSize) -> Void

    init(key: Key, draw: @escaping (GraphicsContext, CGSize) -> Void) {
        self.key = key
        self.draw = draw
    }

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.key == rhs.key }

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in draw(context, size) }
    }
}

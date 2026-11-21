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

/// 分四层绘制：静态层只在尺寸或时段变化时重绘，逐帧层只画会动的元素。
struct PuffCitySceneCanvas: View {
    let recipe: PuffCityRecipe
    let mood: PuffSceneMood
    let clock: DateComponents
    let viewport: PuffCityScene.Viewport
    let isPaused: Bool
    /// 渲染工具与截图使用固定时间；为 nil 时跟随系统时钟。
    var fixedTime: TimeInterval?

    var body: some View {
        ZStack {
            Canvas { context, size in draw(.back, context, size, time: fixedTime ?? 0) }
            animatedLayer(.backMotion)
            Canvas { context, size in draw(.front, context, size, time: fixedTime ?? 0) }
            animatedLayer(.frontMotion)
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

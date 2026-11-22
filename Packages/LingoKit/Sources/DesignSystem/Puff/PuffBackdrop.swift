import SwiftUI

// MARK: - 页面氛围

/// 在页头标题右侧客串的吉祥物（页头右侧没有按钮时才出现）。
public struct PuffPageCameo: Sendable, Equatable {
    public let bird: PuffMascot.Bird
    public let pose: PuffMascot.Pose

    public init(_ bird: PuffMascot.Bird, pose: PuffMascot.Pose = .wave) {
        self.bird = bird
        self.pose = pose
    }
}

public extension EnvironmentValues {
    /// 页面的糖果色调：设置后页头与页面背景画出同色的天空带。
    @Entry var puffPageTint: PuffCandy?
    @Entry var puffPageCameo: PuffPageCameo?
}

public extension View {
    /// 给整页设一个糖果色调：顶部天空带（页头里飘着云），往下渐变回白底，白底上铺很淡的旅行涂鸦。
    /// 放在 `puffPageHeader` 之后，页面内容的底色用 `PuffPageBackdrop()`。`cameo` 让吉祥物坐在页头标题右侧。
    func puffPageTint(_ candy: PuffCandy, cameo: PuffPageCameo? = nil) -> some View {
        environment(\.puffPageTint, candy)
            .environment(\.puffPageCameo, cameo)
    }
}

/// 页面背景：有色调时是天空带 + 淡涂鸦，没有色调时是纯白。
public struct PuffPageBackdrop: View {
    @Environment(\.puffPageTint) private var tint
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init() {}

    public var body: some View {
        ZStack(alignment: .top) {
            Puff.Palette.page
            if let tint {
                PuffSkyBand(candy: tint, showsClouds: false)
                    .frame(maxHeight: .infinity, alignment: .top)
                if !reduceTransparency {
                    PuffDoodleWallpaper(candy: tint)
                        .mask {
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: .clear, location: 0.16),
                                    .init(color: .black, location: 0.3),
                                ],
                                startPoint: .top, endPoint: .bottom
                            )
                        }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 顶部天空带：糖果色浅底从屏幕顶端往下渐变回页面白。页头与页面背景各画一份，几何完全一致，
/// 所以两者叠在一起是连续的；只有页头那份画会飘的云，内容滚到页头下方时云仍在最上层的页头里。
struct PuffSkyBand: View {
    static let height: CGFloat = 300

    let candy: PuffCandy
    let showsClouds: Bool

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                stops: [
                    .init(color: candy.wash.mix(with: candy.base, by: 0.22), location: 0),
                    .init(color: candy.wash.mix(with: candy.base, by: 0.12), location: 0.36),
                    .init(color: Puff.Palette.page, location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
            if showsClouds {
                PuffDriftingClouds()
            }
        }
        .frame(height: Self.height, alignment: .top)
        .frame(maxWidth: .infinity)
    }
}

/// 慢慢飘过的卡通云。页面不可见、App 不在前台或减弱动态效果时停住；在后台线程绘制。
private struct PuffDriftingClouds: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isOnScreen = false

    private struct Cloud {
        let y: CGFloat
        let scale: CGFloat
        let speed: CGFloat
        let phase: CGFloat
    }

    private static let clouds: [Cloud] = [
        Cloud(y: 26, scale: 0.9, speed: 9, phase: 0.08),
        Cloud(y: 62, scale: 0.62, speed: 6, phase: 0.55),
        Cloud(y: 104, scale: 0.78, speed: 7.5, phase: 0.82),
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: reduceMotion || !isOnScreen || scenePhase != .active)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Canvas(rendersAsynchronously: true) { context, size in
                let span = size.width + 160
                for cloud in Self.clouds {
                    let travel = reduceMotion ? 0 : CGFloat(time) * cloud.speed
                    let x = (cloud.phase * span + travel).truncatingRemainder(dividingBy: span) - 80
                    Self.drawCloud(in: context, at: CGPoint(x: x, y: cloud.y), scale: cloud.scale)
                }
            }
        }
        .onAppear { isOnScreen = true }
        .onDisappear { isOnScreen = false }
    }

    static func drawCloud(in context: GraphicsContext, at origin: CGPoint, scale: CGFloat) {
        let puffs: [(CGFloat, CGFloat, CGFloat)] = [(-30, 6, 18), (-10, -6, 24), (16, -2, 20), (34, 8, 14), (0, 10, 22)]
        var path = Path()
        for (dx, dy, r) in puffs {
            let radius = r * scale
            path.addEllipse(in: CGRect(x: origin.x + dx * scale - radius, y: origin.y + dy * scale - radius,
                                       width: radius * 2, height: radius * 2))
        }
        context.fill(path, with: .color(Puff.Palette.card.opacity(0.95)))
    }
}

/// 很淡的旅行涂鸦底纹：星星、爱心、纸飞机、圆圈、小加号、票根。只画一次（尺寸变化时重画）。
struct PuffDoodleWallpaper: View {
    let candy: PuffCandy
    private static let cell: CGFloat = 76

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            var random = SeededRandom(seed: 0xD00D1E)
            let colors: [Color] = [candy.deep, PuffCandy.sunny.deep, PuffCandy.bubblegum.deep, PuffCandy.mint.deep]
            let columns = Int(size.width / Self.cell) + 2
            let rows = Int(size.height / Self.cell) + 2
            for row in 0..<rows {
                for column in 0..<columns {
                    let jitterX = CGFloat(random.next(in: -20...20))
                    let jitterY = CGFloat(random.next(in: -20...20))
                    let offset: CGFloat = row.isMultiple(of: 2) ? 0 : Self.cell / 2
                    let center = CGPoint(x: CGFloat(column) * Self.cell + offset + jitterX,
                                         y: CGFloat(row) * Self.cell + jitterY)
                    let kind = Int(random.next() % 6)
                    let rotation = random.next(in: -0.5...0.5)
                    let size = CGFloat(random.next(in: 11...15))
                    let color = colors[Int(random.next() % UInt64(colors.count))]
                    var piece = context
                    piece.opacity = 0.11
                    piece.translateBy(x: center.x, y: center.y)
                    piece.rotate(by: .radians(rotation))
                    Self.draw(kind: kind, size: size, color: color, in: piece)
                }
            }
        }
    }

    private static func draw(kind: Int, size s: CGFloat, color: Color, in context: GraphicsContext) {
        let stroke = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
        switch kind {
        case 0: // 星星
            var path = Path()
            for point in 0..<10 {
                let radius = point.isMultiple(of: 2) ? s * 0.6 : s * 0.26
                let angle = Double(point) * .pi / 5 - .pi / 2
                let vertex = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
                if point == 0 { path.move(to: vertex) } else { path.addLine(to: vertex) }
            }
            path.closeSubpath()
            context.fill(path, with: .color(color))
        case 1: // 爱心
            let h = s * 0.5
            var path = Path()
            path.move(to: CGPoint(x: 0, y: h * 0.9))
            path.addCurve(to: CGPoint(x: -h, y: -h * 0.15), control1: CGPoint(x: -h * 0.55, y: h * 0.5), control2: CGPoint(x: -h, y: h * 0.2))
            path.addArc(center: CGPoint(x: -h * 0.5, y: -h * 0.2), radius: h * 0.5, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            path.addArc(center: CGPoint(x: h * 0.5, y: -h * 0.2), radius: h * 0.5, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            path.addCurve(to: CGPoint(x: 0, y: h * 0.9), control1: CGPoint(x: h, y: h * 0.2), control2: CGPoint(x: h * 0.55, y: h * 0.5))
            context.fill(path, with: .color(color))
        case 2: // 纸飞机
            var path = Path()
            path.move(to: CGPoint(x: -s * 0.7, y: 0))
            path.addLine(to: CGPoint(x: s * 0.7, y: -s * 0.45))
            path.addLine(to: CGPoint(x: s * 0.1, y: s * 0.5))
            path.addLine(to: CGPoint(x: -s * 0.05, y: s * 0.05))
            path.closeSubpath()
            context.stroke(path, with: .color(color), style: stroke)
        case 3: // 圆圈
            context.stroke(Path(ellipseIn: CGRect(x: -s * 0.4, y: -s * 0.4, width: s * 0.8, height: s * 0.8)),
                           with: .color(color), style: stroke)
        case 4: // 小加号
            var path = Path()
            path.move(to: CGPoint(x: -s * 0.35, y: 0)); path.addLine(to: CGPoint(x: s * 0.35, y: 0))
            path.move(to: CGPoint(x: 0, y: -s * 0.35)); path.addLine(to: CGPoint(x: 0, y: s * 0.35))
            context.stroke(path, with: .color(color), style: stroke)
        default: // 票根
            let rect = CGRect(x: -s * 0.75, y: -s * 0.45, width: s * 1.5, height: s * 0.9)
            context.stroke(Path(roundedRect: rect, cornerRadius: 3), with: .color(color), style: stroke)
            var line = Path()
            line.move(to: CGPoint(x: s * 0.2, y: -s * 0.45)); line.addLine(to: CGPoint(x: s * 0.2, y: s * 0.45))
            context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.5, dash: [2, 2.5]))
        }
    }
}

/// 在页面角落客串的吉祥物：坐在行尾空白处挥手，点一下会蹦。
public struct PuffMascotCameo: View {
    private let bird: PuffMascot.Bird
    private let pose: PuffMascot.Pose
    private let size: CGFloat

    public init(_ bird: PuffMascot.Bird = .gaga, pose: PuffMascot.Pose = .wave, size: CGFloat = 54) {
        self.bird = bird
        self.pose = pose
        self.size = size
    }

    public var body: some View {
        PuffMascot(bird, pose: pose, size: size, showsShadow: false, reactsToTap: true)
            .accessibilityHidden(true)
    }
}

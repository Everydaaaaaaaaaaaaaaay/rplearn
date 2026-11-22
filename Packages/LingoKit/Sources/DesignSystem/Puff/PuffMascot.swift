import SwiftUI

/// 咕咕和嘎嘎：程序化绘制的两只圆滚滚的小鸟。
///
/// - 咕咕：天蓝色，头顶一撮卷毛，系着珊瑚色旅行围巾，负责打招呼、指路和庆祝。
/// - 嘎嘎：淡紫色，扁扁的鸭嘴，头顶两片叶形羽毛和一枚星星发夹，负责提醒、鼓励和讲解。
///
/// 会眨眼、轻轻浮动；挥手、庆祝时翅膀会动。开启“减弱动态效果”时保持静止。
public struct PuffMascot: View {
    public enum Bird: Sendable, Equatable {
        case gugu
        case gaga

        public var name: String {
            switch self {
            case .gugu: "咕咕"
            case .gaga: "嘎嘎"
            }
        }
    }

    public enum Pose: Sendable, Equatable, CaseIterable {
        /// 微笑站好。
        case happy
        /// 举起一边翅膀挥手。
        case wave
        /// 翅膀指向前方。
        case point
        /// 双翅举高，周围撒彩纸。
        case celebrate
        /// 闭眼打盹，冒出 z。
        case sleepy
        /// 歪头张嘴，好奇地看。
        case curious
        /// 眼睛往上看，翅膀托着下巴。
        case thinking
        /// 挺胸眯眼，身边闪着小星星。
        case proud
        /// 鼓起脸颊。
        case pout
        /// 双翅捧着一颗小星星。
        case care
    }

    private let bird: Bird
    private let pose: Pose
    private let size: CGFloat
    private let showsShadow: Bool
    private let reactsToTap: Bool
    @State private var reaction: Reaction?
    @State private var bursts = PuffBurstQueue()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameter reactsToTap: 点一下会蹲下、跳起、落地压扁，换个开心的姿势并迸出小星星。
    ///   只在不处于按钮内部的独立展示位置开启。
    public init(_ bird: Bird, pose: Pose = .happy, size: CGFloat = 120, showsShadow: Bool = true, reactsToTap: Bool = false) {
        self.bird = bird
        self.pose = pose
        self.size = size
        self.showsShadow = showsShadow
        self.reactsToTap = reactsToTap
    }

    private struct Reaction: Equatable {
        let start: Date
        let pose: Pose
        let count: Int
    }

    public var body: some View {
        PuffMascotCanvas(
            bird: bird, pose: reaction?.pose ?? pose, showsShadow: showsShadow, reactionStart: reaction?.start
        )
        .frame(width: size, height: size)
        .overlay {
            if !bursts.bursts.isEmpty {
                PuffBurstLayer(bursts: bursts.bursts)
            }
        }
        .contentShape(Rectangle())
        .gesture(TapGesture().onEnded { react() }, including: reactsToTap ? .all : .subviews)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: reaction?.count ?? 0) { _, count in count > 0 }
        .task(id: reaction?.count ?? 0) {
            guard let current = reaction else { return }
            try? await Task.sleep(for: .seconds(1.5))
            bursts.pruneExpired()
            if reaction == current { reaction = nil }
        }
        .accessibilityHidden(true)
    }

    private func react() {
        let count = (reaction?.count ?? 0) + 1
        let choices: [Pose] = bird == .gugu ? [.celebrate, .wave, .proud] : [.celebrate, .care, .curious]
        reaction = Reaction(start: .now, pose: choices[(count - 1) % choices.count], count: count)
        if !reduceMotion {
            bursts.add(at: CGPoint(x: size / 2, y: size * 0.24))
        }
    }

    /// 蹲下蓄力 → 起跳拉长 → 落地压扁 → 站稳。`hop` 是离地高度（100 单位制），`squash` 正值压扁、负值拉长。
    static func hopMotion(elapsed t: TimeInterval) -> (hop: CGFloat, squash: CGFloat) {
        switch t {
        case ..<0:
            return (0, 0)
        case ..<0.09:
            return (0, CGFloat(t / 0.09) * 0.6)
        case ..<0.47:
            let phase = sin(.pi * (t - 0.09) / 0.38)
            return (CGFloat(phase) * 11, CGFloat(-0.4 * phase))
        case ..<0.72:
            let phase = sin(.pi * (t - 0.47) / 0.25)
            return (0, CGFloat(phase) * 0.75)
        default:
            return (0, 0)
        }
    }
}

/// 吉祥物的逐帧绘制。页面不可见、App 不在前台或减弱动态效果时暂停；绘制在后台线程完成，
/// 页面上的吉祥物不再每秒 30 次占用主线程。
private struct PuffMascotCanvas: View {
    let bird: PuffMascot.Bird
    let pose: PuffMascot.Pose
    let showsShadow: Bool
    let reactionStart: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isOnScreen = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || !isOnScreen || scenePhase != .active)) { timeline in
            let time = reduceMotion ? 1.2 : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3_600)
            let motion = reduceMotion ? (hop: CGFloat(0), squash: CGFloat(0))
                : PuffMascot.hopMotion(elapsed: reactionStart.map { timeline.date.timeIntervalSince($0) } ?? -1)
            Canvas(rendersAsynchronously: true) { context, canvasSize in
                PuffMascotPainter(
                    bird: bird, pose: pose, time: time, showsShadow: showsShadow,
                    hop: motion.hop, squash: motion.squash
                )
                .draw(in: context, size: canvasSize)
            }
        }
        .onAppear { isOnScreen = true }
        .onDisappear { isOnScreen = false }
    }
}

/// 在 100×100 单位里画一只鸟，脚底在 y≈93。
struct PuffMascotPainter {
    let bird: PuffMascot.Bird
    let pose: PuffMascot.Pose
    let time: TimeInterval
    var showsShadow = true
    /// 跳起的高度，单位与画布的 100 单位制相同。
    var hop: CGFloat = 0
    /// 正值压扁、负值拉长，以脚底为支点。
    var squash: CGFloat = 0

    private struct Palette {
        let body: Color
        let shade: Color
        let wing: Color
        let belly = Color(red: 1, green: 0.965, blue: 0.89)
        let beak: Color
        let beakShade: Color
        let feet = Color(red: 1, green: 0.66, blue: 0.33)
        let ink = Color(red: 0.165, green: 0.19, blue: 0.32)
        let blush = Color(red: 1, green: 0.55, blue: 0.66)
    }

    private var palette: Palette {
        switch bird {
        case .gugu:
            Palette(
                body: Color(red: 0.49, green: 0.77, blue: 1),
                shade: Color(red: 0.36, green: 0.66, blue: 0.96),
                wing: Color(red: 0.3, green: 0.6, blue: 0.92),
                beak: Color(red: 1, green: 0.71, blue: 0.28),
                beakShade: Color(red: 0.95, green: 0.58, blue: 0.2)
            )
        case .gaga:
            Palette(
                body: Color(red: 0.73, green: 0.64, blue: 1),
                shade: Color(red: 0.63, green: 0.53, blue: 0.96),
                wing: Color(red: 0.56, green: 0.45, blue: 0.92),
                beak: Color(red: 1, green: 0.78, blue: 0.3),
                beakShade: Color(red: 0.96, green: 0.64, blue: 0.22)
            )
        }
    }

    // MARK: - 动作参数

    private var bob: CGFloat {
        switch pose {
        case .sleepy: CGFloat(sin(time * 1.4)) * 0.8
        case .celebrate: -abs(CGFloat(sin(time * 4.2))) * 4
        default: CGFloat(sin(time * 2.2)) * 1.6
        }
    }

    private var isBlinking: Bool {
        guard pose != .sleepy else { return false }
        return time.truncatingRemainder(dividingBy: 3.7) < 0.13
    }

    private var tilt: Double {
        switch pose {
        case .curious: -9
        case .thinking: 5
        case .proud: -3
        default: CGFloat(sin(time * 1.1)) > 0.97 ? 2 : 0
        }
    }

    // MARK: - 绘制

    func draw(in context: GraphicsContext, size: CGSize) {
        var context = context
        let unit = min(size.width, size.height) / 100
        context.translateBy(x: (size.width - 100 * unit) / 2, y: (size.height - 100 * unit) / 2)
        context.scaleBy(x: unit, y: unit)

        // 地面影子随浮动变化。
        if showsShadow {
            let shadowWidth = (24 - bob * 0.6) * (1 - hop / 30)
            context.fill(Path(ellipseIn: CGRect(x: 50 - shadowWidth, y: 92.5, width: shadowWidth * 2, height: 5)),
                         with: .color(palette.ink.opacity(0.1)))
        }

        var bodyContext = context
        bodyContext.translateBy(x: 50, y: 92 + bob - hop)
        bodyContext.scaleBy(x: 1 + squash * 0.14, y: 1 - squash * 0.14)
        bodyContext.rotate(by: .degrees(tilt))
        bodyContext.translateBy(x: -50, y: -92)

        drawFeet(bodyContext)
        drawBackWing(bodyContext)
        drawBody(bodyContext)
        drawTuft(bodyContext)
        drawFace(bodyContext)
        if bird == .gugu { drawScarf(bodyContext) }
        drawFrontWing(bodyContext)
        drawExtras(context)
    }

    private var bodyPath: Path {
        var path = Path()
        path.move(to: CGPoint(x: 50, y: 24))
        path.addCurve(to: CGPoint(x: 82, y: 66), control1: CGPoint(x: 70, y: 24), control2: CGPoint(x: 82, y: 42))
        path.addCurve(to: CGPoint(x: 50, y: 92), control1: CGPoint(x: 82, y: 84), control2: CGPoint(x: 68, y: 92))
        path.addCurve(to: CGPoint(x: 18, y: 66), control1: CGPoint(x: 32, y: 92), control2: CGPoint(x: 18, y: 84))
        path.addCurve(to: CGPoint(x: 50, y: 24), control1: CGPoint(x: 18, y: 42), control2: CGPoint(x: 30, y: 24))
        path.closeSubpath()
        return path
    }

    private func drawBody(_ context: GraphicsContext) {
        let body = bodyPath
        context.fill(body, with: .color(palette.body))
        var clipped = context
        clipped.clip(to: body)
        clipped.fill(Path(ellipseIn: CGRect(x: 6, y: 66, width: 88, height: 50)), with: .color(palette.shade.opacity(0.55)))
        clipped.fill(Path(ellipseIn: CGRect(x: 26, y: 29, width: 22, height: 13)), with: .color(.white.opacity(0.35)))
        // 奶油色肚皮。
        clipped.fill(Path(ellipseIn: CGRect(x: 31, y: 58, width: 38, height: 36)), with: .color(palette.belly))
    }

    private func drawFeet(_ context: GraphicsContext) {
        for x in [42.0, 58.0] as [CGFloat] {
            var foot = Path()
            foot.move(to: CGPoint(x: x - 4.5, y: 93))
            foot.addLine(to: CGPoint(x: x, y: 89))
            foot.addLine(to: CGPoint(x: x + 4.5, y: 93))
            context.stroke(foot, with: .color(palette.feet), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
    }

    // MARK: 翅膀

    private func wing(_ context: GraphicsContext, pivot: CGPoint, angle: Double, mirrored: Bool) {
        var wingContext = context
        wingContext.translateBy(x: pivot.x, y: pivot.y)
        wingContext.rotate(by: .degrees(angle))
        if mirrored { wingContext.scaleBy(x: -1, y: 1) }
        var shape = Path()
        shape.move(to: CGPoint(x: 0, y: -2))
        shape.addCurve(to: CGPoint(x: -4, y: 24), control1: CGPoint(x: -12, y: 2), control2: CGPoint(x: -12, y: 18))
        shape.addCurve(to: CGPoint(x: 5, y: 6), control1: CGPoint(x: 2, y: 22), control2: CGPoint(x: 6, y: 14))
        shape.closeSubpath()
        wingContext.fill(shape, with: .color(palette.wing))
        wingContext.fill(Path(ellipseIn: CGRect(x: -6, y: 4, width: 5, height: 8)), with: .color(.white.opacity(0.25)))
    }

    private var waveAngle: Double { -125 + sin(time * 7) * 18 }

    /// 远侧（画面左侧）翅膀，在身体后面。
    private func drawBackWing(_ context: GraphicsContext) {
        switch pose {
        case .celebrate:
            wing(context, pivot: CGPoint(x: 22, y: 56), angle: 130 + sin(time * 8) * 14, mirrored: false)
        default:
            break
        }
    }

    /// 身体两侧的翅膀。
    private func drawFrontWing(_ context: GraphicsContext) {
        switch pose {
        case .wave:
            wing(context, pivot: CGPoint(x: 22, y: 60), angle: 12, mirrored: false)
            wing(context, pivot: CGPoint(x: 78, y: 56), angle: waveAngle, mirrored: true)
        case .point:
            wing(context, pivot: CGPoint(x: 22, y: 60), angle: 12, mirrored: false)
            wing(context, pivot: CGPoint(x: 78, y: 60), angle: -80 + sin(time * 3) * 4, mirrored: true)
        case .celebrate:
            wing(context, pivot: CGPoint(x: 78, y: 56), angle: -130 - sin(time * 8) * 14, mirrored: true)
        case .thinking:
            wing(context, pivot: CGPoint(x: 22, y: 60), angle: 12, mirrored: false)
            wing(context, pivot: CGPoint(x: 64, y: 80), angle: 160, mirrored: true)
        case .proud:
            wing(context, pivot: CGPoint(x: 21, y: 62), angle: 40, mirrored: false)
            wing(context, pivot: CGPoint(x: 79, y: 62), angle: -40, mirrored: true)
        case .care:
            wing(context, pivot: CGPoint(x: 26, y: 62), angle: -38, mirrored: false)
            wing(context, pivot: CGPoint(x: 74, y: 62), angle: 38, mirrored: true)
            star(context, center: CGPoint(x: 50, y: 74), radius: 8, color: Color(red: 1, green: 0.8, blue: 0.25))
        default:
            let flap = pose == .happy ? sin(time * 2.2) * 3 : 0
            wing(context, pivot: CGPoint(x: 22, y: 60), angle: 12 + flap, mirrored: false)
            wing(context, pivot: CGPoint(x: 78, y: 60), angle: -12 - flap, mirrored: true)
        }
    }

    // MARK: 头顶

    private func drawTuft(_ context: GraphicsContext) {
        switch bird {
        case .gugu:
            var curl = Path()
            curl.move(to: CGPoint(x: 47, y: 26))
            curl.addCurve(to: CGPoint(x: 58, y: 11), control1: CGPoint(x: 44, y: 16), control2: CGPoint(x: 50, y: 10))
            curl.addCurve(to: CGPoint(x: 59, y: 19), control1: CGPoint(x: 64, y: 12), control2: CGPoint(x: 63, y: 18))
            curl.addCurve(to: CGPoint(x: 53, y: 26), control1: CGPoint(x: 55, y: 20), control2: CGPoint(x: 52, y: 22))
            curl.closeSubpath()
            context.fill(curl, with: .color(palette.body))
            var small = Path()
            small.move(to: CGPoint(x: 44, y: 26))
            small.addQuadCurve(to: CGPoint(x: 39, y: 16), control: CGPoint(x: 38, y: 22))
            small.addQuadCurve(to: CGPoint(x: 49, y: 25), control: CGPoint(x: 46, y: 18))
            small.closeSubpath()
            context.fill(small, with: .color(palette.shade))
        case .gaga:
            for (dx, angle) in [(-5.0, -24.0), (5.0, 22.0)] as [(CGFloat, Double)] {
                var leafContext = context
                leafContext.translateBy(x: 50 + dx, y: 27)
                leafContext.rotate(by: .degrees(angle))
                var leaf = Path()
                leaf.move(to: .zero)
                leaf.addQuadCurve(to: CGPoint(x: 0, y: -16), control: CGPoint(x: -8, y: -8))
                leaf.addQuadCurve(to: .zero, control: CGPoint(x: 8, y: -8))
                leafContext.fill(leaf, with: .color(dx < 0 ? palette.shade : palette.body))
            }
            star(context, center: CGPoint(x: 62, y: 28), radius: 5.5, color: Color(red: 1, green: 0.8, blue: 0.25))
        }
    }

    // MARK: 脸

    private func drawFace(_ context: GraphicsContext) {
        let ink = palette.ink
        let lookUp: CGFloat = pose == .thinking ? -1.6 : 0
        let eyeY: CGFloat = 48
        for side in [-1.0, 1.0] as [CGFloat] {
            let x = 50 + side * 11
            switch eyeStyle {
            case .open(let scale):
                let height = isBlinking ? 1.2 : 11 * scale
                let width = 8.6 * scale
                context.fill(Path(ellipseIn: CGRect(x: x - width / 2, y: eyeY - height / 2 + lookUp, width: width, height: height)), with: .color(ink))
                if !isBlinking {
                    context.fill(Path(ellipseIn: CGRect(x: x - 0.6, y: eyeY - height / 2 + 1.4 + lookUp, width: 3.6, height: 3.6)), with: .color(.white))
                    context.fill(Path(ellipseIn: CGRect(x: x - 2.6, y: eyeY + 1.6 + lookUp, width: 1.8, height: 1.8)), with: .color(.white.opacity(0.8)))
                }
            case .smile:
                var arc = Path()
                arc.move(to: CGPoint(x: x - 4.5, y: eyeY + 1.5))
                arc.addQuadCurve(to: CGPoint(x: x + 4.5, y: eyeY + 1.5), control: CGPoint(x: x, y: eyeY - 5.5))
                context.stroke(arc, with: .color(ink), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
            case .closed:
                var arc = Path()
                arc.move(to: CGPoint(x: x - 4.5, y: eyeY))
                arc.addQuadCurve(to: CGPoint(x: x + 4.5, y: eyeY), control: CGPoint(x: x, y: eyeY + 4.5))
                context.stroke(arc, with: .color(ink), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            case .halfLid:
                context.fill(Path(ellipseIn: CGRect(x: x - 4, y: eyeY - 3, width: 8, height: 8)), with: .color(ink))
                context.fill(Path(CGRect(x: x - 5, y: eyeY - 5, width: 10, height: 4.4)), with: .color(palette.body))
                context.stroke({ var p = Path(); p.move(to: CGPoint(x: x - 4.6, y: eyeY - 0.6)); p.addLine(to: CGPoint(x: x + 4.6, y: eyeY - 0.6)); return p }(),
                               with: .color(ink), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            }
            let blushSize: CGFloat = pose == .pout ? 1.35 : 1
            context.fill(Path(ellipseIn: CGRect(x: x + side * 4.5 - 5 * blushSize, y: eyeY + 7, width: 10 * blushSize, height: 5.5 * blushSize)),
                         with: .color(palette.blush.opacity(0.55)))
        }
        drawBeak(context)
    }

    private enum EyeStyle {
        case open(CGFloat)
        case smile
        case closed
        case halfLid
    }

    private var eyeStyle: EyeStyle {
        switch pose {
        case .celebrate, .proud, .care: .smile
        case .sleepy: .closed
        case .pout: .halfLid
        case .curious: .open(1.12)
        default: .open(1)
        }
    }

    private func drawBeak(_ context: GraphicsContext) {
        switch bird {
        case .gugu:
            var beak = Path()
            beak.move(to: CGPoint(x: 45.5, y: 53))
            beak.addQuadCurve(to: CGPoint(x: 54.5, y: 53), control: CGPoint(x: 50, y: 51))
            beak.addQuadCurve(to: CGPoint(x: 50, y: pose == .curious ? 61 : 59), control: CGPoint(x: 53.5, y: 57))
            beak.addQuadCurve(to: CGPoint(x: 45.5, y: 53), control: CGPoint(x: 46.5, y: 57))
            beak.closeSubpath()
            context.fill(beak, with: .color(palette.beak))
            if pose == .curious || pose == .celebrate || pose == .wave {
                context.fill(Path(ellipseIn: CGRect(x: 47.6, y: 55.5, width: 4.8, height: 3)), with: .color(palette.beakShade))
            }
        case .gaga:
            let open = pose == .curious || pose == .celebrate || pose == .wave
            context.fill(Path(roundedRect: CGRect(x: 42, y: 52, width: 16, height: 6), cornerRadius: 3), with: .color(palette.beak))
            if open {
                context.fill(Path(roundedRect: CGRect(x: 43.5, y: 57, width: 13, height: 4.5), cornerRadius: 2.25), with: .color(palette.beakShade))
            } else {
                context.stroke({ var p = Path(); p.move(to: CGPoint(x: 44.5, y: 55.4)); p.addLine(to: CGPoint(x: 55.5, y: 55.4)); return p }(),
                               with: .color(palette.beakShade), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            }
        }
    }

    // MARK: 围巾与装饰

    private func drawScarf(_ context: GraphicsContext) {
        let coral = Color(red: 1, green: 0.42, blue: 0.37)
        let coralShade = Color(red: 0.9, green: 0.32, blue: 0.3)
        var band = Path()
        band.move(to: CGPoint(x: 27, y: 62))
        band.addQuadCurve(to: CGPoint(x: 73, y: 62), control: CGPoint(x: 50, y: 72))
        band.addLine(to: CGPoint(x: 72, y: 68))
        band.addQuadCurve(to: CGPoint(x: 28, y: 68), control: CGPoint(x: 50, y: 78))
        band.closeSubpath()
        context.fill(band, with: .color(coral))
        let sway = CGFloat(sin(time * 2.4)) * 1.5
        var tail = Path()
        tail.move(to: CGPoint(x: 64, y: 68))
        tail.addLine(to: CGPoint(x: 71 + sway, y: 82))
        tail.addLine(to: CGPoint(x: 65 + sway, y: 84))
        tail.addLine(to: CGPoint(x: 59, y: 70))
        tail.closeSubpath()
        context.fill(tail, with: .color(coralShade))
        for stripe in 0..<2 {
            let y = 75.5 + CGFloat(stripe) * 4
            context.fill(Path(roundedRect: CGRect(x: 63 + sway * 0.7, y: y, width: 6, height: 1.4), cornerRadius: 0.7), with: .color(.white.opacity(0.7)))
        }
    }

    private func drawExtras(_ context: GraphicsContext) {
        switch pose {
        case .celebrate:
            let colors: [Color] = [
                Color(red: 1, green: 0.49, blue: 0.67), Color(red: 0.3, green: 0.65, blue: 1),
                Color(red: 1, green: 0.77, blue: 0.24), Color(red: 0.24, green: 0.83, blue: 0.6),
            ]
            for index in 0..<10 {
                let phase = (time * 0.45 + Double(index) * 0.13).truncatingRemainder(dividingBy: 1)
                let x = 8 + CGFloat(index) * 9.4 + CGFloat(sin(time * 2 + Double(index))) * 2
                let y = -2 + CGFloat(phase) * 70
                var piece = context
                piece.translateBy(x: x, y: y)
                piece.rotate(by: .radians(time * 3 + Double(index)))
                piece.fill(Path(roundedRect: CGRect(x: -2, y: -1, width: 4, height: 2.4), cornerRadius: 0.6),
                           with: .color(colors[index % colors.count].opacity(1 - phase * 0.6)))
            }
        case .sleepy:
            let phase = CGFloat((time * 0.5).truncatingRemainder(dividingBy: 1))
            for (index, offset) in [0.0, 0.5].enumerated() {
                let p = (phase + CGFloat(offset)).truncatingRemainder(dividingBy: 1)
                context.draw(
                    Text("z").font(.system(size: 9 + p * 6 + CGFloat(index), weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 0.55, green: 0.62, blue: 0.85).opacity(1 - Double(p))),
                    at: CGPoint(x: 74 + p * 12, y: 26 - p * 18)
                )
            }
        case .thinking:
            for (index, radius) in [1.6, 2.4, 3.4].enumerated() {
                let pulse = 0.6 + 0.4 * sin(time * 3 - Double(index))
                context.fill(Path(ellipseIn: CGRect(x: 72 + CGFloat(index) * 6 - radius, y: 24 - CGFloat(index) * 6 - radius,
                                                    width: radius * 2, height: radius * 2)),
                             with: .color(Color(red: 0.62, green: 0.68, blue: 0.86).opacity(pulse)))
            }
        case .proud, .care:
            for (index, point) in [CGPoint(x: 14, y: 30), CGPoint(x: 86, y: 38), CGPoint(x: 82, y: 14)].enumerated() {
                let twinkle = 0.4 + 0.6 * (0.5 + 0.5 * sin(time * 3 + Double(index) * 2))
                sparkle(context, center: point, radius: 3.6 + CGFloat(index % 2), color: Color(red: 1, green: 0.8, blue: 0.3).opacity(twinkle))
            }
        case .curious:
            let pulse = 0.5 + 0.5 * sin(time * 2.6)
            sparkle(context, center: CGPoint(x: 84, y: 24), radius: 4 + CGFloat(pulse) * 1.5, color: Color(red: 0.3, green: 0.65, blue: 1).opacity(0.85))
        default:
            break
        }
    }

    private func star(_ context: GraphicsContext, center: CGPoint, radius: CGFloat, color: Color) {
        var path = Path()
        for index in 0..<10 {
            let r = index % 2 == 0 ? radius : radius * 0.48
            let angle = Double(index) / 10 * 2 * .pi - .pi / 2
            let point = CGPoint(x: center.x + CGFloat(cos(angle)) * r, y: center.y + CGFloat(sin(angle)) * r)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        context.fill(path, with: .color(color))
        context.stroke(path, with: .color(color.opacity(0.6)), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
    }

    private func sparkle(_ context: GraphicsContext, center: CGPoint, radius: CGFloat, color: Color) {
        var path = Path()
        path.move(to: CGPoint(x: center.x, y: center.y - radius))
        path.addQuadCurve(to: CGPoint(x: center.x + radius, y: center.y), control: CGPoint(x: center.x + radius * 0.18, y: center.y - radius * 0.18))
        path.addQuadCurve(to: CGPoint(x: center.x, y: center.y + radius), control: CGPoint(x: center.x + radius * 0.18, y: center.y + radius * 0.18))
        path.addQuadCurve(to: CGPoint(x: center.x - radius, y: center.y), control: CGPoint(x: center.x - radius * 0.18, y: center.y + radius * 0.18))
        path.addQuadCurve(to: CGPoint(x: center.x, y: center.y - radius), control: CGPoint(x: center.x - radius * 0.18, y: center.y - radius * 0.18))
        context.fill(path, with: .color(color))
    }
}

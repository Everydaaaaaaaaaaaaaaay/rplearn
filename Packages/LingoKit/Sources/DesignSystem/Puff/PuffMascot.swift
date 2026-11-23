import SwiftUI

/// 咕咕和嘎嘎：沿用改版前定稿形象的三维渲染小鸟。
///
/// - 咕咕：天蓝色，头顶一撮卷毛，奶油色心形脸和肚皮，翅膀带浅色斑点，负责打招呼、指路和庆祝。
/// - 嘎嘎：淡紫色，头顶三片叶形羽毛，眼睛以下是奶油色绒毛脸颊，外眼角睫毛上翘，负责提醒、鼓励和讲解。
///
/// 每个姿态是一张 Blender 渲染图（`Tools/ArtPipeline/Blender/mascot3d.py`），
/// 呼吸、眨眼、挥动翅膀、跳跃和彩纸等动作在这里叠加。开启“减弱动态效果”时保持静止。
public struct PuffMascot: View {
    public enum Bird: String, Sendable, Equatable {
        case gugu
        case gaga

        public var name: String {
            switch self {
            case .gugu: "咕咕"
            case .gaga: "嘎嘎"
            }
        }
    }

    public enum Pose: String, Sendable, Equatable, CaseIterable {
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
        /// 抱着翅膀、半垂眼皮、鼓起脸颊。
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
        PuffMascotStage(
            bird: bird, pose: reaction?.pose ?? pose, size: size, showsShadow: showsShadow, reactionStart: reaction?.start
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

/// 一个姿态的渲染图：本体、可选的闭眼图和单独渲染、可以摆动的翅膀。
struct PuffMascotSprite {
    struct Wing {
        let name: String
        /// 肩膀转轴在图中的位置（左上为原点）。
        let pivot: UnitPoint
        /// 摆动方向：画面左翅为 1，右翅为 -1，挥手时顺着翅尖来回。
        let direction: Double
    }

    let bird: PuffMascot.Bird
    let pose: PuffMascot.Pose

    /// 渲染时脚底所在的高度（图高的比例），影子和压扁都以这里为支点。
    static let feetY: CGFloat = 0.93
    private static let leftShoulder = UnitPoint(x: 0.3298, y: 0.5089)
    private static let rightShoulder = UnitPoint(x: 0.6574, y: 0.5129)

    var name: String { "mascot-\(bird.rawValue)-\(pose.rawValue)" }

    /// 闭眼图；本来就闭着眼或眯眼笑的姿态不眨眼。
    var blinkName: String? {
        switch pose {
        case .celebrate, .sleepy, .proud, .care: nil
        default: name + "-blink"
        }
    }

    var wings: [Wing] {
        switch pose {
        case .wave:
            [Wing(name: name + "-wing-r", pivot: Self.rightShoulder, direction: 1)]
        case .celebrate:
            [Wing(name: name + "-wing-l", pivot: Self.leftShoulder, direction: 1),
             Wing(name: name + "-wing-r", pivot: Self.rightShoulder, direction: -1)]
        default:
            []
        }
    }
}

/// 吉祥物的动作层。页面不可见、App 不在前台或减弱动态效果时暂停；
/// 每帧只改图片的位移、缩放和旋转，不重画。
private struct PuffMascotStage: View {
    let bird: PuffMascot.Bird
    let pose: PuffMascot.Pose
    let size: CGFloat
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
            PuffMascotFrame(
                sprite: PuffMascotSprite(bird: bird, pose: pose), size: size, time: time,
                isStill: reduceMotion, showsShadow: showsShadow, hop: motion.hop, squash: motion.squash
            )
        }
        .onAppear { isOnScreen = true }
        .onDisappear { isOnScreen = false }
    }
}

/// 一帧：影子、身体（呼吸/跳跃）、翅膀和周围的小装饰。
struct PuffMascotFrame: View {
    let sprite: PuffMascotSprite
    let size: CGFloat
    let time: TimeInterval
    var isStill = false
    var showsShadow = true
    var hop: CGFloat = 0
    var squash: CGFloat = 0

    private var unit: CGFloat { size / 100 }

    /// 上下浮动（100 单位制）：庆祝时一蹦一蹦，打盹时几乎不动。
    private var bob: CGFloat {
        guard !isStill else { return 0 }
        switch sprite.pose {
        case .sleepy: return CGFloat(sin(time * 1.4)) * 0.5
        case .celebrate: return -abs(CGFloat(sin(time * 4.2))) * 4
        default: return CGFloat(sin(time * 2.2)) * 0.8
        }
    }

    /// 呼吸：以脚底为支点轻轻拉长、变宽。
    private var breath: CGFloat {
        guard !isStill else { return 0 }
        return CGFloat(sin(time * (sprite.pose == .sleepy ? 1.4 : 2.2) + 0.8)) * 0.012
    }

    private var isBlinking: Bool {
        guard !isStill, sprite.blinkName != nil else { return false }
        let phase = sprite.bird == .gugu ? 0 : 1.3
        return (time + phase).truncatingRemainder(dividingBy: 3.7) < 0.13
    }

    private func wingAngle(_ wing: PuffMascotSprite.Wing) -> Double {
        guard !isStill else { return 0 }
        switch sprite.pose {
        case .wave: return sin(time * 7) * 16 * wing.direction
        case .celebrate: return sin(time * 8) * 12 * wing.direction
        default: return 0
        }
    }

    var body: some View {
        let feet = UnitPoint(x: 0.5, y: PuffMascotSprite.feetY)
        ZStack {
            if showsShadow {
                let width = (26 - bob * 0.6) * (1 - hop / 30)
                Ellipse()
                    .fill(Color(red: 0.165, green: 0.19, blue: 0.32).opacity(0.12))
                    .frame(width: width * 2 * unit, height: 5 * unit)
                    .blur(radius: unit * 0.9)
                    .position(x: 50 * unit, y: 94 * unit)
            }
            ZStack {
                art(isBlinking ? sprite.blinkName ?? sprite.name : sprite.name)
                ForEach(sprite.wings, id: \.name) { wing in
                    art(wing.name).rotationEffect(.degrees(wingAngle(wing)), anchor: wing.pivot)
                }
            }
            .scaleEffect(x: 1 + squash * 0.14 - breath * 0.6, y: 1 - squash * 0.14 + breath, anchor: feet)
            .offset(y: (bob - hop) * unit)
            Canvas { context, canvasSize in
                PuffMascotExtras(pose: sprite.pose, time: time).draw(in: context, size: canvasSize)
            }
        }
        .frame(width: size, height: size)
    }

    private func art(_ name: String) -> some View {
        Image(name, bundle: .module)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

/// 身边的小装饰：彩纸、z、思考的泡泡和闪光，画在 100×100 单位里。
struct PuffMascotExtras {
    let pose: PuffMascot.Pose
    let time: TimeInterval

    func draw(in context: GraphicsContext, size: CGSize) {
        var context = context
        let unit = min(size.width, size.height) / 100
        context.translateBy(x: (size.width - 100 * unit) / 2, y: (size.height - 100 * unit) / 2)
        context.scaleBy(x: unit, y: unit)
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
                    at: CGPoint(x: 76 + p * 12, y: 24 - p * 18)
                )
            }
        case .thinking:
            for (index, radius) in [1.6, 2.4, 3.4].enumerated() {
                let pulse = 0.6 + 0.4 * sin(time * 3 - Double(index))
                context.fill(Path(ellipseIn: CGRect(x: 74 + CGFloat(index) * 6 - radius, y: 22 - CGFloat(index) * 6 - radius,
                                                    width: radius * 2, height: radius * 2)),
                             with: .color(Color(red: 0.62, green: 0.68, blue: 0.86).opacity(pulse)))
            }
        case .proud, .care:
            for (index, point) in [CGPoint(x: 13, y: 30), CGPoint(x: 87, y: 40), CGPoint(x: 83, y: 14)].enumerated() {
                let twinkle = 0.4 + 0.6 * (0.5 + 0.5 * sin(time * 3 + Double(index) * 2))
                sparkle(context, center: point, radius: 3.6 + CGFloat(index % 2), color: Color(red: 1, green: 0.8, blue: 0.3).opacity(twinkle))
            }
        case .curious:
            let pulse = 0.5 + 0.5 * sin(time * 2.6)
            sparkle(context, center: CGPoint(x: 85, y: 22), radius: 4 + CGFloat(pulse) * 1.5, color: Color(red: 0.3, green: 0.65, blue: 1).opacity(0.85))
        default:
            break
        }
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

import SwiftUI

/// 咕咕和嘎嘎：改版前的 2D 动作插画（`Assets/Brand/Mascots/ui-pack-v1/GuyujiMascots.xcassets`，
/// 由 `project.yml` 编入 App，所以从主 Bundle 读取）。
///
/// - 咕咕：天蓝色，头顶一撮卷毛，奶油色脸和肚皮，翅膀带斑点。四张图：招呼、探路（拿地图）、欢呼、休息。
/// - 嘎嘎：淡紫色，头顶叶形羽毛，奶油色绒毛脸颊。四张图：思考、鼓嘴、鼓励（捧星星）、得意。
///
/// 十种姿态映射到这八张图（`artName`）。浮动、呼吸、点击跳起、彩纸和 z 在这里叠加；
/// 插画自带的问号、星星、地图不再另画。开启“减弱动态效果”时保持静止。
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
        /// 开心地站着。
        case happy
        /// 挥手打招呼。
        case wave
        /// 指路、带路。
        case point
        /// 欢呼庆祝，周围撒彩纸。
        case celebrate
        /// 闭眼休息，冒出 z。
        case sleepy
        /// 好奇地看。
        case curious
        /// 认真思考。
        case thinking
        /// 得意、认可。
        case proud
        /// 鼓起脸颊。
        case pout
        /// 捧着星星鼓励。
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

    /// 每只鸟只有四张图，没有对应图的姿态用最接近的一张。
    nonisolated static func artName(_ bird: Bird, _ pose: Pose) -> String {
        switch bird {
        case .gugu:
            switch pose {
            case .happy, .wave, .pout, .care: "mascot_gugu_welcome"
            case .point, .curious, .thinking: "mascot_gugu_explore"
            case .celebrate, .proud: "mascot_gugu_celebrate"
            case .sleepy: "mascot_gugu_rest"
            }
        case .gaga:
            switch pose {
            case .curious, .thinking, .point: "mascot_gaga_think"
            case .pout: "mascot_gaga_pout"
            case .care, .sleepy: "mascot_gaga_care"
            case .happy, .wave, .celebrate, .proud: "mascot_gaga_proud"
            }
        }
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

/// 吉祥物的动作层。页面不可见、App 不在前台或减弱动态效果时暂停；
/// 每帧只改图片的位移和缩放，不重画。
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
                bird: bird, pose: pose, size: size, time: time,
                isStill: reduceMotion, showsShadow: showsShadow, hop: motion.hop, squash: motion.squash
            )
        }
        .onAppear { isOnScreen = true }
        .onDisappear { isOnScreen = false }
    }
}

/// 一帧：影子、插画（浮动、呼吸、跳跃）和周围的小装饰。
struct PuffMascotFrame: View {
    let bird: PuffMascot.Bird
    let pose: PuffMascot.Pose
    let size: CGFloat
    let time: TimeInterval
    var isStill = false
    var showsShadow = true
    var hop: CGFloat = 0
    var squash: CGFloat = 0

    /// 插画在吉祥物框里的位置：高占 86%，底边在 95%。插画的脚在图高约 97.5% 处，
    /// 落在框的约 93% 高度上，与地面影子对齐；头顶留出浮动、跳跃和装饰的空间。
    static let artHeight: CGFloat = 0.86
    static let artBottom: CGFloat = 0.95
    private static let feet = UnitPoint(x: 0.5, y: 0.975)

    private var unit: CGFloat { size / 100 }
    private var art: String { PuffMascot.artName(bird, pose) }

    /// 上下浮动（100 单位制）：庆祝时一蹦一蹦，打盹时几乎不动。
    private var bob: CGFloat {
        guard !isStill else { return 0 }
        switch pose {
        case .sleepy: return CGFloat(sin(time * 1.4)) * 0.5
        case .celebrate: return -abs(CGFloat(sin(time * 4.2))) * 4
        default: return CGFloat(sin(time * 2.2)) * 0.8
        }
    }

    /// 呼吸：以脚底为支点轻轻拉长、变宽。
    private var breath: CGFloat {
        guard !isStill else { return 0 }
        return CGFloat(sin(time * (pose == .sleepy ? 1.4 : 2.2) + 0.8)) * 0.012
    }

    var body: some View {
        let side = size * Self.artHeight
        ZStack {
            if showsShadow {
                let width = (24 - bob * 0.6) * (1 - hop / 30)
                Ellipse()
                    .fill(Color(red: 0.165, green: 0.19, blue: 0.32).opacity(0.12))
                    .frame(width: width * 2 * unit, height: 5 * unit)
                    .blur(radius: unit * 0.9)
                    .position(x: 50 * unit, y: 93.5 * unit)
            }
            Image(art)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
                .frame(width: side, height: side)
                .scaleEffect(x: 1 + squash * 0.14 - breath * 0.6, y: 1 - squash * 0.14 + breath, anchor: Self.feet)
                .position(x: size / 2, y: size * Self.artBottom - side / 2)
                .offset(y: (bob - hop) * unit)
            if !isStill {
                Canvas { context, canvasSize in
                    PuffMascotExtras(pose: pose, art: art, time: time).draw(in: context, size: canvasSize)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

/// 插画上没有的动态小装饰：庆祝时落下的彩纸、打盹时飘起的 z，画在 100×100 单位里。
struct PuffMascotExtras {
    let pose: PuffMascot.Pose
    let art: String
    let time: TimeInterval

    func draw(in context: GraphicsContext, size: CGSize) {
        var context = context
        let unit = min(size.width, size.height) / 100
        context.translateBy(x: (size.width - 100 * unit) / 2, y: (size.height - 100 * unit) / 2)
        context.scaleBy(x: unit, y: unit)
        if pose == .celebrate {
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
        }
        // 只有休息的咕咕闭着眼；嘎嘎没有打盹的图，不配 z。
        if art == "mascot_gugu_rest" {
            let phase = CGFloat((time * 0.5).truncatingRemainder(dividingBy: 1))
            for (index, offset) in [0.0, 0.5].enumerated() {
                let p = (phase + CGFloat(offset)).truncatingRemainder(dividingBy: 1)
                context.draw(
                    Text("z").font(.system(size: 9 + p * 6 + CGFloat(index), weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 0.55, green: 0.62, blue: 0.85).opacity(1 - Double(p))),
                    at: CGPoint(x: 80 + p * 12, y: 20 - p * 16)
                )
            }
        }
    }
}

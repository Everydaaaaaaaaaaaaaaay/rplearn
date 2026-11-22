import SwiftUI

/// 一次迸发：从 `origin` 向外飞出几颗糖果色的小星星、爱心和圆点，约 0.9 秒后淡出。
struct PuffBurst: Identifiable, Equatable {
    let id = UUID()
    let origin: CGPoint
    let start: Date
    let seed: UInt64

    init(origin: CGPoint, start: Date = .now) {
        self.origin = origin
        self.start = start
        self.seed = UInt64.random(in: 0...UInt64(UInt32.max))
    }
}

enum PuffBurstPainter {
    static let duration: TimeInterval = 0.9
    /// 粒子可以飞出宿主视图的距离。
    static let reach: CGFloat = 56
    private static let colors: [Color] = PuffCandy.all.map(\.base)

    static func draw(_ bursts: [PuffBurst], at date: Date, in context: GraphicsContext) {
        for burst in bursts {
            let progress = date.timeIntervalSince(burst.start) / duration
            guard progress >= 0, progress < 1 else { continue }
            var random = SeededRandom(seed: burst.seed)
            let count = 8
            let eased = 1 - pow(1 - progress, 3)
            let opacity = progress < 0.55 ? 1 : 1 - (progress - 0.55) / 0.45
            let pop = progress < 0.18 ? progress / 0.18 : 1 - (progress - 0.18) * 0.45
            for index in 0..<count {
                let angle = Double(index) / Double(count) * 2 * .pi - .pi / 2 + random.next(in: -0.35...0.35)
                let distance = random.next(in: 26...48)
                let size = random.next(in: 7...11) * pop
                let spin = random.next(in: -2.5...2.5)
                let point = CGPoint(
                    x: burst.origin.x + cos(angle) * distance * eased,
                    // 飞出去之后轻轻往下落。
                    y: burst.origin.y + sin(angle) * distance * eased + 16 * progress * progress
                )
                var piece = context
                piece.opacity = opacity
                piece.translateBy(x: point.x, y: point.y)
                piece.rotate(by: .radians(spin * progress))
                let color = colors[(index + Int(burst.seed % UInt64(colors.count))) % colors.count]
                switch index % 3 {
                case 0: piece.fill(star(size: size), with: .color(color))
                case 1: piece.fill(heart(size: size), with: .color(color))
                default: piece.fill(Path(ellipseIn: CGRect(x: -size * 0.32, y: -size * 0.32, width: size * 0.64, height: size * 0.64)), with: .color(color))
                }
            }
        }
    }

    private static func star(size: CGFloat) -> Path {
        var path = Path()
        for point in 0..<10 {
            let radius = point.isMultiple(of: 2) ? size * 0.55 : size * 0.24
            let angle = Double(point) * .pi / 5 - .pi / 2
            let vertex = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
            if point == 0 { path.move(to: vertex) } else { path.addLine(to: vertex) }
        }
        path.closeSubpath()
        return path
    }

    private static func heart(size: CGFloat) -> Path {
        let s = size * 0.5
        var path = Path()
        path.move(to: CGPoint(x: 0, y: s * 0.9))
        path.addCurve(to: CGPoint(x: -s, y: -s * 0.15), control1: CGPoint(x: -s * 0.55, y: s * 0.5), control2: CGPoint(x: -s, y: s * 0.2))
        path.addArc(center: CGPoint(x: -s * 0.5, y: -s * 0.2), radius: s * 0.5, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        path.addArc(center: CGPoint(x: s * 0.5, y: -s * 0.2), radius: s * 0.5, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        path.addCurve(to: CGPoint(x: 0, y: s * 0.9), control1: CGPoint(x: s, y: s * 0.2), control2: CGPoint(x: s * 0.55, y: s * 0.5))
        path.closeSubpath()
        return path
    }
}

/// 只在有迸发进行时才运行的绘制层，四周比宿主多出 `reach`，粒子不会被裁掉。
struct PuffBurstLayer: View {
    let bursts: [PuffBurst]

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, _ in
                var context = context
                context.translateBy(x: PuffBurstPainter.reach, y: PuffBurstPainter.reach)
                PuffBurstPainter.draw(bursts, at: timeline.date, in: context)
            }
        }
        .padding(-PuffBurstPainter.reach)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 管理一组迸发：加入新的、过期后清空，让绘制层随之停下。
@MainActor
struct PuffBurstQueue {
    private(set) var bursts: [PuffBurst] = []

    mutating func add(at origin: CGPoint) {
        let now = Date.now
        bursts.removeAll { now.timeIntervalSince($0.start) > PuffBurstPainter.duration }
        bursts.append(PuffBurst(origin: origin, start: now))
    }

    mutating func pruneExpired() {
        let now = Date.now
        bursts.removeAll { now.timeIntervalSince($0.start) >= PuffBurstPainter.duration }
    }
}

private struct PuffTapBurstModifier: ViewModifier {
    let isEnabled: Bool
    @State private var queue = PuffBurstQueue()
    @State private var taps = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                SpatialTapGesture().onEnded { value in
                    queue.add(at: value.location)
                    taps += 1
                },
                including: isEnabled && !reduceMotion ? .all : .subviews
            )
            .overlay {
                if !queue.bursts.isEmpty {
                    PuffBurstLayer(bursts: queue.bursts)
                }
            }
            .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.45), trigger: taps)
            .task(id: taps) {
                guard taps > 0 else { return }
                try? await Task.sleep(for: .seconds(PuffBurstPainter.duration + 0.05))
                queue.pruneExpired()
            }
    }
}

public extension View {
    /// 点一下，在手指处迸出几颗糖果色小星星和爱心。与原有点击同时生效，不拦截按钮和滚动；
    /// “减弱动态效果”时关闭。
    func puffTapBurst(isEnabled: Bool = true) -> some View {
        modifier(PuffTapBurstModifier(isEnabled: isEnabled))
    }
}

/// 可重复的伪随机数，让同一次迸发每帧的粒子轨迹一致。
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func next(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + Double(next() % 10_000) / 10_000 * (range.upperBound - range.lowerBound)
    }
}

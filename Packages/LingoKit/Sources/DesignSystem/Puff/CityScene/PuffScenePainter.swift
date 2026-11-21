import SwiftUI

/// 卡通城市场景的时段。由城市当地时间决定，与 App 深浅色无关：
/// 深夜打开伦敦，看到的就是星星和亮灯的窗户。
public enum PuffSceneMood: Sendable, Equatable, CaseIterable {
    case day
    case dusk
    case night

    /// 6–7 点、17–19 点为晨昏，其余按昼夜划分。
    public static func at(hour: Int) -> PuffSceneMood {
        switch hour {
        case 7..<17: .day
        case 5..<7, 17..<19: .dusk
        default: .night
        }
    }
}

/// 场景内使用的不透明 RGB。全部绘制颜色都经过时段换算，避免在各个地标里分别写夜景色。
struct SceneInk: Sendable, Equatable {
    var r: Double
    var g: Double
    var b: Double

    init(_ hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }

    init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    func mixed(with other: SceneInk, _ amount: Double) -> SceneInk {
        SceneInk(
            r: r + (other.r - r) * amount,
            g: g + (other.g - g) * amount,
            b: b + (other.b - b) * amount
        )
    }

    var color: Color { Color(red: r, green: g, blue: b) }
}

/// 一个时段的天空、水面与地面基色。地标颜色由 `PuffScenePainter.c(_:)` 统一换算。
struct PuffSceneAtmosphere: Sendable {
    let skyTop: SceneInk
    let skyBottom: SceneInk
    let cloud: SceneInk
    let cloudOpacity: Double
    let far: SceneInk
    let farShade: SceneInk
    let water: SceneInk
    let waterLight: SceneInk
    let grass: SceneInk
    let grassShade: SceneInk
    let road: SceneInk
    let roadLine: SceneInk

    static func forMood(_ mood: PuffSceneMood) -> PuffSceneAtmosphere {
        switch mood {
        case .day:
            PuffSceneAtmosphere(
                skyTop: SceneInk(0xBFE4FF), skyBottom: SceneInk(0xF4FAFF),
                cloud: SceneInk(0xFFFFFF), cloudOpacity: 1,
                far: SceneInk(0xD5E3F7), farShade: SceneInk(0xC4D6F1),
                water: SceneInk(0x8DCBFF), waterLight: SceneInk(0xC4E5FF),
                grass: SceneInk(0xB9E7A3), grassShade: SceneInk(0x9CD98A),
                road: SceneInk(0xF5F2EC), roadLine: SceneInk(0xFFFFFF)
            )
        case .dusk:
            PuffSceneAtmosphere(
                skyTop: SceneInk(0xA8B2F0), skyBottom: SceneInk(0xFFD8C4),
                cloud: SceneInk(0xFFEDE8), cloudOpacity: 0.95,
                far: SceneInk(0xCDBFE6), farShade: SceneInk(0xBBAEDC),
                water: SceneInk(0x9DAEEA), waterLight: SceneInk(0xF6C9C3),
                grass: SceneInk(0xA9CF9D), grassShade: SceneInk(0x90BE8A),
                road: SceneInk(0xEDE2E3), roadLine: SceneInk(0xFFF6F2)
            )
        case .night:
            PuffSceneAtmosphere(
                skyTop: SceneInk(0x1B2254), skyBottom: SceneInk(0x3A4588),
                cloud: SceneInk(0x5A64A3), cloudOpacity: 0.55,
                far: SceneInk(0x2B3372), farShade: SceneInk(0x252C64),
                water: SceneInk(0x26357A), waterLight: SceneInk(0x5867B0),
                grass: SceneInk(0x2D5A61), grassShade: SceneInk(0x254C55),
                road: SceneInk(0x394071), roadLine: SceneInk(0x59609A)
            )
        }
    }
}

/// 在 720×180 的设计坐标中绘制。调用方已把 GraphicsContext 缩放平移到该坐标系。
struct PuffScenePainter {
    static let width: CGFloat = 720
    static let height: CGFloat = 180
    /// 远岸或地面的基线。
    static let horizon: CGFloat = 140
    /// 近处道路上车辆轮胎落点。
    static let roadBase: CGFloat = 173

    var ctx: GraphicsContext
    let mood: PuffSceneMood
    let atmosphere: PuffSceneAtmosphere
    /// 动画时间（秒）。静态图层传 0。
    let time: TimeInterval
    /// 城市当地时间，用于钟面。
    let clock: DateComponents

    init(ctx: GraphicsContext, mood: PuffSceneMood, time: TimeInterval, clock: DateComponents) {
        self.ctx = ctx
        self.mood = mood
        self.atmosphere = .forMood(mood)
        self.time = time
        self.clock = clock
    }

    var isNight: Bool { mood == .night }

    // MARK: - 颜色

    private static let duskTint = SceneInk(0xFFB49C)
    private static let duskShade = SceneInk(0x6D5A9A)
    private static let nightTint = SceneInk(0x1E2660)

    /// 把白天设计色换算到当前时段。
    func ink(_ hex: UInt32) -> SceneInk {
        toned(SceneInk(hex))
    }

    func toned(_ base: SceneInk) -> SceneInk {
        switch mood {
        case .day: return base
        case .dusk: return base.mixed(with: Self.duskTint, 0.14).mixed(with: Self.duskShade, 0.1)
        case .night: return base.mixed(with: Self.nightTint, 0.62)
        }
    }

    /// 任意混合色同样按时段换算。
    func tone(_ base: SceneInk) -> Color { toned(base).color }

    func c(_ hex: UInt32) -> Color { ink(hex).color }

    /// 窗户：白天按设计色，夜里亮起暖黄色灯光。
    func window(_ hex: UInt32, lit: Bool = true) -> Color {
        isNight && lit ? SceneInk(0xFFE38F).color : c(hex)
    }

    // MARK: - 基础图形

    func fill(_ path: Path, _ color: Color) {
        ctx.fill(path, with: .color(color))
    }

    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: Color, r: CGFloat = 0) {
        let frame = CGRect(x: x, y: y, width: w, height: h)
        let path = r > 0
            ? Path(roundedRect: frame, cornerRadius: min(r, w / 2, h / 2), style: .continuous)
            : Path(frame)
        ctx.fill(path, with: .color(color))
    }

    /// 只圆上方两个角，用于建筑与车厢顶部。
    func topRounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: Color, r: CGFloat) {
        let radius = min(r, w / 2, h)
        let path = Path(
            roundedRect: CGRect(x: x, y: y, width: w, height: h),
            cornerRadii: RectangleCornerRadii(topLeading: radius, bottomLeading: 0, bottomTrailing: 0, topTrailing: radius),
            style: .continuous
        )
        ctx.fill(path, with: .color(color))
    }

    func circle(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat, _ color: Color) {
        ctx.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)), with: .color(color))
    }

    func ellipse(_ x: CGFloat, _ y: CGFloat, _ rx: CGFloat, _ ry: CGFloat, _ color: Color) {
        ctx.fill(Path(ellipseIn: CGRect(x: x - rx, y: y - ry, width: rx * 2, height: ry * 2)), with: .color(color))
    }

    func poly(_ points: [CGPoint], _ color: Color) {
        guard let first = points.first else { return }
        var path = Path()
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        path.closeSubpath()
        ctx.fill(path, with: .color(color))
    }

    func line(_ from: CGPoint, _ to: CGPoint, _ color: Color, width: CGFloat) {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    func stroke(_ path: Path, _ color: Color, width: CGFloat) {
        ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    /// 半圆穹顶，底边位于 `baseY`。
    func dome(_ x: CGFloat, _ baseY: CGFloat, _ rx: CGFloat, _ ry: CGFloat, _ color: Color) {
        var path = Path()
        path.move(to: CGPoint(x: x - rx, y: baseY))
        path.addQuadCurve(to: CGPoint(x: x, y: baseY - ry), control: CGPoint(x: x - rx, y: baseY - ry))
        path.addQuadCurve(to: CGPoint(x: x + rx, y: baseY), control: CGPoint(x: x + rx, y: baseY - ry))
        path.closeSubpath()
        ctx.fill(path, with: .color(color))
    }

    /// 小尖顶。
    func spire(_ x: CGFloat, _ baseY: CGFloat, width: CGFloat, height: CGFloat, _ color: Color) {
        poly([
            CGPoint(x: x - width / 2, y: baseY),
            CGPoint(x: x + width / 2, y: baseY),
            CGPoint(x: x, y: baseY - height),
        ], color)
    }

    /// 规则排列的小窗。
    func windowGrid(
        x: CGFloat, y: CGFloat, columns: Int, rows: Int,
        w: CGFloat, h: CGFloat, gapX: CGFloat, gapY: CGFloat,
        color: UInt32, litPattern: Int = 3
    ) {
        for row in 0..<rows {
            for column in 0..<columns {
                let lit = (row * 7 + column * 3 + litPattern) % 4 != 0
                rect(
                    x + CGFloat(column) * (w + gapX),
                    y + CGFloat(row) * (h + gapY),
                    w, h,
                    window(color, lit: lit),
                    r: min(w, h) * 0.35
                )
            }
        }
    }

    /// 可重复的伪随机数，保证同一城市每次绘制完全一致。
    static func noise(_ seed: Int) -> CGFloat {
        var value = UInt64(truncatingIfNeeded: seed &* 0x9E3779B1 &+ 0x7F4A7C15)
        value ^= value >> 15
        value = value &* 0x2C1B3C6D
        value ^= value >> 12
        value = value &* 0x297A2D39
        value ^= value >> 15
        return CGFloat(value % 10_000) / 10_000
    }
}

import DesignSystem
import SwiftUI

/// 视觉稿以 iPhone 17 Pro 的 402 pt 宽度为参考；高度严格保持 825 × 1906 母版比例。
/// 任何机型适配都只能缩放这个画布，不能分别重算图片与入口的位置。
enum TravelDeskLayout {
    static let canvasWidth: CGFloat = 402
    static let canvasHeight: CGFloat = canvasWidth * 1906 / 825

    /// 参考画布中最低入口（登录）的视觉与点击范围底边，含少量微光余量。
    /// 短屏按此高度整体缩放，保证入口停在系统 Tab 栏上方。
    static let interactiveContentBottom: CGFloat = 682
}

/// 每个入口都使用承载物自身的局部平面，而不是套用同一组“伪透视”。
/// 参数按 825 × 1906 的母版逐物件校准；足迹方向同时表达悬浮高度与环境光方向。
struct SceneHologramPlane {
    let rotationZ: Double
    let tiltX: Double
    let tiltY: Double
    let perspective: CGFloat
    let scaleX: CGFloat
    let scaleY: CGFloat
    let footprintOffset: CGSize
    let extrusionOffset: CGSize

    static let identityHolder = SceneHologramPlane(
        rotationZ: -13,
        tiltX: 8,
        tiltY: -2,
        perspective: 0.2,
        scaleX: 1,
        scaleY: 0.985,
        footprintOffset: CGSize(width: 3, height: 13),
        extrusionOffset: CGSize(width: 1, height: 2.6)
    )
    static let camera = SceneHologramPlane(
        rotationZ: 7,
        tiltX: 6,
        tiltY: 1,
        perspective: 0.18,
        scaleX: 1,
        scaleY: 0.99,
        footprintOffset: CGSize(width: 1, height: 13),
        extrusionOffset: CGSize(width: 0.5, height: 2.6)
    )
    static let wallet = SceneHologramPlane(
        rotationZ: 13,
        tiltX: 7,
        tiltY: -2,
        perspective: 0.2,
        scaleX: 1,
        scaleY: 0.98,
        footprintOffset: CGSize(width: -3, height: 13),
        extrusionOffset: CGSize(width: -0.8, height: 2.6)
    )
    static let tablet = SceneHologramPlane(
        rotationZ: 4,
        tiltX: 6,
        tiltY: -1,
        perspective: 0.18,
        scaleX: 1,
        scaleY: 0.985,
        footprintOffset: CGSize(width: -1, height: 14),
        extrusionOffset: CGSize(width: -0.4, height: 2.8)
    )
    static let phrasebook = SceneHologramPlane(
        rotationZ: -12,
        tiltX: 7,
        tiltY: 1.5,
        perspective: 0.2,
        scaleX: 1,
        scaleY: 0.98,
        footprintOffset: CGSize(width: 3, height: 13),
        extrusionOffset: CGSize(width: 0.8, height: 2.6)
    )
    static let watch = SceneHologramPlane(
        rotationZ: 16,
        tiltX: 9,
        tiltY: -2.5,
        perspective: 0.22,
        scaleX: 1,
        scaleY: 0.97,
        footprintOffset: CGSize(width: -3, height: 14),
        extrusionOffset: CGSize(width: -0.8, height: 2.9)
    )
    static let phone = SceneHologramPlane(
        rotationZ: 3,
        tiltX: 6,
        tiltY: 0,
        perspective: 0.18,
        scaleX: 1,
        scaleY: 0.98,
        footprintOffset: CGSize(width: -2, height: 14),
        extrusionOffset: CGSize(width: -0.6, height: 2.8)
    )
}

struct SceneHologram<Content: View>: View {
    let plane: SceneHologramPlane
    let tint: Color
    let content: Content

    init(
        plane: SceneHologramPlane,
        tint: Color = .sceneHologramYellow,
        @ViewBuilder content: () -> Content
    ) {
        self.plane = plane
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        layers
    }

    private var layers: some View {
        DSHologramSurface(
            transform: DSHologramTransform(
                rotationZ: plane.rotationZ,
                tiltX: plane.tiltX,
                tiltY: plane.tiltY,
                perspective: plane.perspective,
                scaleX: plane.scaleX,
                scaleY: plane.scaleY,
                footprintOffset: plane.footprintOffset,
                extrusionOffset: plane.extrusionOffset
            )
        ) {
            content
        }
    }
}

struct SceneHologramText: View {
    let value: String
    let size: CGFloat
    let weight: Font.Weight
    let tint: Color

    init(
        _ value: String,
        size: CGFloat,
        weight: Font.Weight,
        tint: Color = .sceneHologramYellow
    ) {
        self.value = value
        self.size = size
        self.weight = weight
        self.tint = tint
    }

    var body: some View {
        DSHologramText(
            value,
            size: size,
            weight: weight,
            tint: tint,
            glowColor: .sceneHologramGlowYellow
        )
    }
}

enum SceneHologramGlyph {
    case system(String)
    case coinStacks
    case journeyBook
    case bookmarkStar
    case account
}

struct SceneHologramIcon: View {
    let glyph: SceneHologramGlyph
    let size: CGFloat
    let tint: Color

    init(
        glyph: SceneHologramGlyph,
        size: CGFloat,
        tint: Color = .sceneHologramYellow
    ) {
        self.glyph = glyph
        self.size = size
        self.tint = tint
    }

    @ViewBuilder
    var body: some View {
        switch glyph {
        case .bookmarkStar:
            DSHologramBookmarkIcon(
                size: size,
                tint: tint,
                glowColor: .sceneHologramGlowYellow
            )
        default:
            decoratedGlyph
        }
    }

    private var decoratedGlyph: some View {
        glyphBody
            .frame(width: size, height: size)
            .foregroundStyle(tint.opacity(0.99))
            .shadow(color: Color.sceneHologramGlowYellow.opacity(0.38), radius: 6.2)
            .shadow(color: Color.sceneHologramGlowYellow.opacity(0.64), radius: 2.2)
            .shadow(color: .white.opacity(0.24), radius: 0.6)
            .shadow(color: .black.opacity(0.26), radius: 0.7, y: 0.8)
    }

    @ViewBuilder
    private var glyphBody: some View {
        switch glyph {
        case .system(let name):
            Image(systemName: name)
                .font(.system(size: size, weight: .medium))
                .symbolRenderingMode(.monochrome)
        case .coinStacks:
            CoinStacksGlyph()
                .stroke(
                    tint.opacity(0.99),
                    style: glyphStrokeStyle
                )
                .padding(size * 0.04)
        case .journeyBook:
            JourneyBookGlyph()
                .stroke(
                    tint.opacity(0.99),
                    style: glyphStrokeStyle
                )
                .padding(size * 0.035)
        case .bookmarkStar:
            ZStack {
                BookmarkGlyph()
                    .stroke(
                        tint.opacity(0.99),
                        style: glyphStrokeStyle
                    )
                StarGlyph()
                    .fill(tint.opacity(0.99))
                    .frame(width: size * 0.34, height: size * 0.34)
                    .offset(y: -size * 0.15)
            }
            .padding(size * 0.04)
        case .account:
            ZStack {
                AccountCloudGlyph()
                    .stroke(
                        tint.opacity(0.99),
                        style: glyphStrokeStyle
                    )
                AccountPersonGlyph()
                    .fill(tint.opacity(0.99))
            }
            .padding(size * 0.035)
        }
    }

    private var glyphStrokeStyle: StrokeStyle {
        StrokeStyle(
            lineWidth: max(1.7, size * 0.052),
            lineCap: .round,
            lineJoin: .round
        )
    }
}

/// 参考稿中的三组硬币：用统一线宽绘制真实叠放关系，替代含义不明确的双圆点符号。
struct CoinStacksGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        appendStack(
            to: &path,
            in: rect,
            centerX: 0.2,
            top: 0.43,
            bottom: 0.83,
            width: 0.32,
            tiers: 3
        )
        appendStack(
            to: &path,
            in: rect,
            centerX: 0.8,
            top: 0.38,
            bottom: 0.83,
            width: 0.32,
            tiers: 3
        )
        appendStack(
            to: &path,
            in: rect,
            centerX: 0.5,
            top: 0.14,
            bottom: 0.83,
            width: 0.36,
            tiers: 5
        )
        return path
    }

    private func appendStack(
        to path: inout Path,
        in rect: CGRect,
        centerX: CGFloat,
        top: CGFloat,
        bottom: CGFloat,
        width: CGFloat,
        tiers: Int
    ) {
        let stackWidth = rect.width * width
        let ellipseHeight = rect.height * 0.12
        let center = rect.minX + rect.width * centerX
        let left = center - stackWidth / 2
        let right = center + stackWidth / 2
        let topY = rect.minY + rect.height * top
        let bottomY = rect.minY + rect.height * bottom

        path.addEllipse(
            in: CGRect(
                x: left,
                y: topY,
                width: stackWidth,
                height: ellipseHeight
            )
        )
        path.move(to: CGPoint(x: left, y: topY + ellipseHeight / 2))
        path.addLine(to: CGPoint(x: left, y: bottomY))
        path.addCurve(
            to: CGPoint(x: right, y: bottomY),
            control1: CGPoint(x: left, y: bottomY + ellipseHeight * 0.58),
            control2: CGPoint(x: right, y: bottomY + ellipseHeight * 0.58)
        )
        path.addLine(to: CGPoint(x: right, y: topY + ellipseHeight / 2))

        for tier in 1 ..< tiers {
            let fraction = CGFloat(tier) / CGFloat(tiers)
            let y = topY + ellipseHeight / 2 + (bottomY - topY) * fraction
            path.move(to: CGPoint(x: left, y: y))
            path.addCurve(
                to: CGPoint(x: right, y: y),
                control1: CGPoint(x: left, y: y + ellipseHeight * 0.5),
                control2: CGPoint(x: right, y: y + ellipseHeight * 0.5)
            )
        }
    }
}

/// 展开的旅行手册与右页上升路线，保持参考稿的开放、成长语义。
struct JourneyBookGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let point: (CGFloat, CGFloat) -> CGPoint = { x, y in
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        var path = Path()

        path.move(to: point(0.5, 0.84))
        path.addCurve(
            to: point(0.08, 0.7),
            control1: point(0.36, 0.72),
            control2: point(0.2, 0.68)
        )
        path.addLine(to: point(0.08, 0.18))
        path.addCurve(
            to: point(0.5, 0.31),
            control1: point(0.23, 0.14),
            control2: point(0.39, 0.19)
        )
        path.addLine(to: point(0.5, 0.84))
        path.addCurve(
            to: point(0.92, 0.7),
            control1: point(0.64, 0.72),
            control2: point(0.8, 0.68)
        )
        path.addLine(to: point(0.92, 0.18))
        path.addCurve(
            to: point(0.5, 0.31),
            control1: point(0.77, 0.14),
            control2: point(0.61, 0.19)
        )

        path.move(to: point(0.59, 0.59))
        path.addLine(to: point(0.69, 0.48))
        path.addLine(to: point(0.76, 0.54))
        path.addLine(to: point(0.87, 0.39))
        path.move(to: point(0.78, 0.39))
        path.addLine(to: point(0.87, 0.39))
        path.addLine(to: point(0.87, 0.48))
        return path
    }
}

struct BookmarkGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY + rect.height * 0.04))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.88, y: rect.minY + rect.height * 0.04),
            control: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.005)
        )
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.88, y: rect.minY + rect.height * 0.94))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.7))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY + rect.height * 0.94))
        path.closeSubpath()
        return path
    }
}

struct StarGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * 0.46
        var path = Path()
        for index in 0 ..< 10 {
            let radius = index.isMultiple(of: 2) ? outerRadius : innerRadius
            let angle = -CGFloat.pi / 2 + CGFloat(index) * CGFloat.pi / 5
            let point = CGPoint(
                x: center.x + CGFloat(cos(Double(angle))) * radius,
                y: center.y + CGFloat(sin(Double(angle))) * radius
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

/// 参考稿中的账户入口：开放底边的云形轮廓承托人物剪影。
struct AccountCloudGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let point: (CGFloat, CGFloat) -> CGPoint = { x, y in
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        var path = Path()

        path.move(to: point(0.32, 0.42))
        path.addCurve(
            to: point(0.68, 0.42),
            control1: point(0.33, 0.14),
            control2: point(0.67, 0.14)
        )
        path.addCurve(
            to: point(0.73, 0.84),
            control1: point(0.91, 0.38),
            control2: point(1, 0.72)
        )
        path.move(to: point(0.27, 0.84))
        path.addCurve(
            to: point(0.32, 0.42),
            control1: point(0, 0.78),
            control2: point(0.09, 0.38)
        )
        return path
    }
}

struct AccountPersonGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        path.addEllipse(
            in: CGRect(
                x: rect.minX + rect.width * 0.39,
                y: rect.minY + rect.height * 0.38,
                width: rect.width * 0.22,
                height: rect.height * 0.22
            )
        )
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.minY + rect.height * 0.84))
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.72, y: rect.minY + rect.height * 0.84),
            control1: CGPoint(x: rect.minX + rect.width * 0.3, y: rect.minY + rect.height * 0.61),
            control2: CGPoint(x: rect.minX + rect.width * 0.7, y: rect.minY + rect.height * 0.61)
        )
        path.closeSubpath()
        return path
    }
}

struct SceneHologramButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.955 : 1)
            .brightness(configuration.isPressed ? 0.075 : 0)
            .animation(
                .spring(response: 0.28, dampingFraction: 0.82),
                value: configuration.isPressed
            )
    }
}

extension Color {
    /// 从参考图发光文字和图标的实体核心反推，约 RGB(254, 249, 236)。
    static let sceneHologramYellow = Color(red: 0.996, green: 0.976, blue: 0.925)

    /// 参考图主体外侧黄色衰减层的代表色，约 RGB(249, 232, 182)。
    static let sceneHologramGlowYellow = Color(red: 0.976, green: 0.91, blue: 0.714)
}

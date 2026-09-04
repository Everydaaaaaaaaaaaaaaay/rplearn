import SwiftUI

/// 摄影场景入口共用的材质参数。SwiftUI 与 Metal 渲染路径都读取这里，避免首页和
/// “我的”页分别手调后产生色温、溢光范围与实体边缘上的漂移。
public struct DSHologramEffectMetrics: Sendable {
    public let outerGlowRadius: CGFloat
    public let outerGlowOpacity: Double
    public let innerGlowRadius: CGFloat
    public let innerGlowOpacity: Double
    public let edgeLightRadius: CGFloat
    public let edgeLightOpacity: Double
    public let edgeLightOffset: CGSize
    public let depthEdgeRadius: CGFloat
    public let depthEdgeOpacity: Double
    public let depthEdgeOffset: CGSize

    public init(
        outerGlowRadius: CGFloat,
        outerGlowOpacity: Double,
        innerGlowRadius: CGFloat,
        innerGlowOpacity: Double,
        edgeLightRadius: CGFloat,
        edgeLightOpacity: Double,
        edgeLightOffset: CGSize,
        depthEdgeRadius: CGFloat,
        depthEdgeOpacity: Double,
        depthEdgeOffset: CGSize
    ) {
        self.outerGlowRadius = outerGlowRadius
        self.outerGlowOpacity = outerGlowOpacity
        self.innerGlowRadius = innerGlowRadius
        self.innerGlowOpacity = innerGlowOpacity
        self.edgeLightRadius = edgeLightRadius
        self.edgeLightOpacity = edgeLightOpacity
        self.edgeLightOffset = edgeLightOffset
        self.depthEdgeRadius = depthEdgeRadius
        self.depthEdgeOpacity = depthEdgeOpacity
        self.depthEdgeOffset = depthEdgeOffset
    }
}

public enum DSHologramMaterial {
    public static let coreRed = 1.0
    public static let coreGreen = 0.978
    public static let coreBlue = 0.91
    public static let coreOpacity = 0.99

    public static let glowRed = 1.0
    public static let glowGreen = 0.90
    public static let glowBlue = 0.64

    public static let footprintRadius: CGFloat = 5.8
    public static let footprintOpacity = 0.13
    public static let extrusionRadius: CGFloat = 0.7
    public static let extrusionOpacity = 0.16

    /// “我的”页文字：宽而淡的环境光、窄而克制的内光，以及两个不足 1pt 的实体边。
    public static let text = DSHologramEffectMetrics(
        outerGlowRadius: 6.2,
        outerGlowOpacity: 0.32 * 0.52,
        innerGlowRadius: 2.3,
        innerGlowOpacity: 0.60 * 0.72,
        edgeLightRadius: 0.9,
        edgeLightOpacity: 0.38 * 0.70,
        edgeLightOffset: CGSize(width: 0.55, height: 0.8),
        depthEdgeRadius: 0.8,
        depthEdgeOpacity: 0.28,
        depthEdgeOffset: CGSize(width: 0, height: 0.65)
    )

    /// “我的”页绝大多数入口图标所用参数；比文字略亮，但核心仍由不透明象牙白承载。
    public static let sceneIcon = DSHologramEffectMetrics(
        outerGlowRadius: 6.2,
        outerGlowOpacity: 0.38,
        innerGlowRadius: 2.2,
        innerGlowOpacity: 0.64,
        edgeLightRadius: 0.6,
        edgeLightOpacity: 0.24,
        edgeLightOffset: .zero,
        depthEdgeRadius: 0.7,
        depthEdgeOpacity: 0.26,
        depthEdgeOffset: CGSize(width: 0, height: 0.8)
    )

    /// DesignSystem 对外通用的 SF Symbol 参数。
    public static let symbol = DSHologramEffectMetrics(
        outerGlowRadius: 6.2,
        outerGlowOpacity: 0.42,
        innerGlowRadius: 2.2,
        innerGlowOpacity: 0.70,
        edgeLightRadius: 0.6,
        edgeLightOpacity: 0.28,
        edgeLightOffset: .zero,
        depthEdgeRadius: 0.7,
        depthEdgeOpacity: 0.28,
        depthEdgeOffset: CGSize(width: 0, height: 0.8)
    )
}

public enum DSHologramPalette {
    /// 场景入口的实体核心：接近白色，只保留足以区别系统纯白的暖黄色。
    public static let ivory = Color(
        red: DSHologramMaterial.coreRed,
        green: DSHologramMaterial.coreGreen,
        blue: DSHologramMaterial.coreBlue
    )

    /// 场景入口的发光层：比核心更暖，叠加后形成淡金而非霓虹黄。
    public static let glow = Color(
        red: DSHologramMaterial.glowRed,
        green: DSHologramMaterial.glowGreen,
        blue: DSHologramMaterial.glowBlue
    )
}

public extension Color {
    static let dsHologramIvory = DSHologramPalette.ivory
    static let dsHologramGlow = DSHologramPalette.glow
}

/// “我的”场景中悬浮标记所使用的空间参数。
public struct DSHologramTransform: Sendable {
    public let rotationZ: Double
    public let tiltX: Double
    public let tiltY: Double
    public let perspective: CGFloat
    public let scaleX: CGFloat
    public let scaleY: CGFloat
    public let footprintOffset: CGSize
    public let extrusionOffset: CGSize

    public init(
        rotationZ: Double = 0,
        tiltX: Double = 0,
        tiltY: Double = 0,
        perspective: CGFloat = 0.18,
        scaleX: CGFloat = 1,
        scaleY: CGFloat = 1,
        footprintOffset: CGSize = CGSize(width: 0, height: 10),
        extrusionOffset: CGSize = CGSize(width: 0, height: 2.4)
    ) {
        self.rotationZ = rotationZ
        self.tiltX = tiltX
        self.tiltY = tiltY
        self.perspective = perspective
        self.scaleX = scaleX
        self.scaleY = scaleY
        self.footprintOffset = footprintOffset
        self.extrusionOffset = extrusionOffset
    }
}

/// 与“我的”页相同的悬浮、挤出和落影路径。
///
/// 阴影由同一份内容表面合成，避免为每个入口复制整棵 View 树。
public struct DSHologramLift<Content: View>: View {
    private let footprintOffset: CGSize
    private let extrusionOffset: CGSize
    private let content: Content

    public init(
        footprintOffset: CGSize = CGSize(width: 0, height: 10),
        extrusionOffset: CGSize = CGSize(width: 0, height: 2.4),
        @ViewBuilder content: () -> Content
    ) {
        self.footprintOffset = footprintOffset
        self.extrusionOffset = extrusionOffset
        self.content = content()
    }

    public var body: some View {
        content
            .shadow(
                color: .black.opacity(DSHologramMaterial.footprintOpacity),
                radius: DSHologramMaterial.footprintRadius,
                x: footprintOffset.width,
                y: footprintOffset.height
            )
            .shadow(
                color: .black.opacity(DSHologramMaterial.extrusionOpacity),
                radius: DSHologramMaterial.extrusionRadius,
                x: extrusionOffset.width,
                y: extrusionOffset.height
            )
    }
}

/// 将悬浮层贴合到摄影物件的局部平面。
public struct DSHologramSurface<Content: View>: View {
    private let transform: DSHologramTransform
    private let content: Content

    public init(
        transform: DSHologramTransform,
        @ViewBuilder content: () -> Content
    ) {
        self.transform = transform
        self.content = content()
    }

    public var body: some View {
        DSHologramLift(
            footprintOffset: transform.footprintOffset,
            extrusionOffset: transform.extrusionOffset
        ) {
            content
        }
        .scaleEffect(x: transform.scaleX, y: transform.scaleY)
        .rotationEffect(.degrees(transform.rotationZ))
        .rotation3DEffect(
            .degrees(transform.tiltX),
            axis: (x: 1, y: 0, z: 0),
            anchor: .center,
            perspective: transform.perspective
        )
        .rotation3DEffect(
            .degrees(transform.tiltY),
            axis: (x: 0, y: 1, z: 0),
            anchor: .center,
            perspective: transform.perspective
        )
    }
}

/// “我的”页文字的同源 2.5D 渲染器；色彩可按语义替换。
public struct DSHologramText: View {
    private let value: String
    private let size: CGFloat
    private let weight: Font.Weight
    private let tint: Color
    private let glowColor: Color
    private let alignment: TextAlignment
    private let lineSpacing: CGFloat

    public init(
        _ value: String,
        size: CGFloat,
        weight: Font.Weight,
        tint: Color,
        glowColor: Color,
        alignment: TextAlignment = .leading,
        lineSpacing: CGFloat = 0
    ) {
        self.value = value
        self.size = size
        self.weight = weight
        self.tint = tint
        self.glowColor = glowColor
        self.alignment = alignment
        self.lineSpacing = lineSpacing
    }

    public var body: some View {
        Text(value)
            .font(.system(size: size, weight: weight, design: .rounded))
            .tracking(size >= 20 ? -0.45 : 0.08)
            .multilineTextAlignment(alignment)
            .lineSpacing(lineSpacing)
            .foregroundStyle(tint.opacity(DSHologramMaterial.coreOpacity))
            .textRenderer(DSHologramTextRenderer(tint: tint, glowColor: glowColor))
    }
}

/// 与全息文字共用核心、双层泛光和接触边的 SF Symbol。
public struct DSHologramSymbol: View {
    private let systemName: String
    private let size: CGFloat
    private let weight: Font.Weight
    private let tint: Color
    private let glowColor: Color

    public init(
        systemName: String,
        size: CGFloat,
        weight: Font.Weight = .medium,
        tint: Color = .dsHologramIvory,
        glowColor: Color = .dsHologramGlow
    ) {
        self.systemName = systemName
        self.size = size
        self.weight = weight
        self.tint = tint
        self.glowColor = glowColor
    }

    public var body: some View {
        let metrics = DSHologramMaterial.symbol

        Image(systemName: systemName)
            .font(.system(size: size, weight: weight))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(tint.opacity(DSHologramMaterial.coreOpacity))
            .shadow(color: glowColor.opacity(metrics.outerGlowOpacity), radius: metrics.outerGlowRadius)
            .shadow(color: glowColor.opacity(metrics.innerGlowOpacity), radius: metrics.innerGlowRadius)
            .shadow(color: .white.opacity(metrics.edgeLightOpacity), radius: metrics.edgeLightRadius)
            .shadow(
                color: .black.opacity(metrics.depthEdgeOpacity),
                radius: metrics.depthEdgeRadius,
                x: metrics.depthEdgeOffset.width,
                y: metrics.depthEdgeOffset.height
            )
            .accessibilityHidden(true)
    }
}

/// 场景入口统一的即时按压反馈；视觉向承载物表面压近，不绘制按钮底板。
public struct DSHologramButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.955)
            .brightness(configuration.isPressed ? 0.075 : 0)
            .opacity(configuration.isPressed ? 0.96 : 1)
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.14)
                    : .spring(response: 0.28, dampingFraction: 0.82),
                value: configuration.isPressed
            )
    }
}

public extension ButtonStyle where Self == DSHologramButtonStyle {
    static var dsHologram: DSHologramButtonStyle {
        DSHologramButtonStyle()
    }
}

/// “我的”页收藏入口的原始书签与五角星路径。
public struct DSHologramBookmarkIcon: View {
    private let size: CGFloat
    private let tint: Color
    private let glowColor: Color
    private let isElevated: Bool
    private let strokeWidth: CGFloat?

    public init(
        size: CGFloat,
        tint: Color,
        glowColor: Color,
        isElevated: Bool = true,
        strokeWidth: CGFloat? = nil
    ) {
        self.size = size
        self.tint = tint
        self.glowColor = glowColor
        self.isElevated = isElevated
        self.strokeWidth = strokeWidth
    }

    @ViewBuilder
    public var body: some View {
        let metrics = DSHologramMaterial.symbol

        if isElevated {
            glyph
                .shadow(color: glowColor.opacity(metrics.outerGlowOpacity), radius: metrics.outerGlowRadius)
                .shadow(color: glowColor.opacity(metrics.innerGlowOpacity), radius: metrics.innerGlowRadius)
                .shadow(color: .white.opacity(0.24), radius: metrics.edgeLightRadius)
                .shadow(color: .black.opacity(0.26), radius: metrics.depthEdgeRadius, y: 0.8)
                .accessibilityHidden(true)
        } else {
            glyph
                .accessibilityHidden(true)
        }
    }

    private var glyph: some View {
        ZStack {
            DSHologramBookmarkShape()
                .stroke(tint.opacity(DSHologramMaterial.coreOpacity), style: glyphStrokeStyle)
            DSHologramStarShape()
                .fill(tint.opacity(DSHologramMaterial.coreOpacity))
                .frame(width: size * 0.34, height: size * 0.34)
                .offset(y: -size * 0.15)
        }
        .padding(size * 0.04)
        .frame(width: size, height: size)
        .foregroundStyle(tint.opacity(DSHologramMaterial.coreOpacity))
    }

    private var glyphStrokeStyle: StrokeStyle {
        StrokeStyle(
            lineWidth: strokeWidth ?? max(1.7, size * 0.052),
            lineCap: .round,
            lineJoin: .round
        )
    }
}

private struct DSHologramBookmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY + rect.height * 0.04))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.88, y: rect.minY + rect.height * 0.04),
            control: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.005)
        )
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.88, y: rect.minY + rect.height * 0.94))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.70))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY + rect.height * 0.94))
        path.closeSubpath()
        return path
    }
}

private struct DSHologramStarShape: Shape {
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

private struct DSHologramTextRenderer: TextRenderer {
    let tint: Color
    let glowColor: Color

    var displayPadding: EdgeInsets {
        EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        let metrics = DSHologramMaterial.text

        var depthEdge = context
        depthEdge.addFilter(
            .shadow(
                color: .black.opacity(metrics.depthEdgeOpacity),
                radius: metrics.depthEdgeRadius,
                x: metrics.depthEdgeOffset.width,
                y: metrics.depthEdgeOffset.height,
                options: .shadowOnly
            ),
            options: .linearColor
        )
        draw(layout, in: &depthEdge)

        var outerGlow = context
        outerGlow.opacity = metrics.outerGlowOpacity
        outerGlow.addFilter(
            .shadow(
                color: glowColor,
                radius: metrics.outerGlowRadius,
                options: .shadowOnly
            ),
            options: .linearColor
        )
        draw(layout, in: &outerGlow)

        var innerGlow = context
        innerGlow.opacity = metrics.innerGlowOpacity
        innerGlow.addFilter(
            .shadow(
                color: glowColor,
                radius: metrics.innerGlowRadius,
                options: .shadowOnly
            ),
            options: .linearColor
        )
        draw(layout, in: &innerGlow)

        var edgeLight = context
        edgeLight.opacity = metrics.edgeLightOpacity
        edgeLight.translateBy(x: metrics.edgeLightOffset.width, y: metrics.edgeLightOffset.height)
        edgeLight.addFilter(
            .shadow(
                color: .white,
                radius: metrics.edgeLightRadius,
                options: .shadowOnly
            ),
            options: .linearColor
        )
        draw(layout, in: &edgeLight)

        draw(layout, in: &context)
    }

    private func draw(_ layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line {
                context.draw(run)
            }
        }
    }
}

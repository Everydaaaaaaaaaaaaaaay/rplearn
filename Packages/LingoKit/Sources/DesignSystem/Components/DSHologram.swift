import SwiftUI

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
                color: .black.opacity(0.13),
                radius: 5.8,
                x: footprintOffset.width,
                y: footprintOffset.height
            )
            .shadow(
                color: .black.opacity(0.16),
                radius: 0.7,
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
            .foregroundStyle(tint.opacity(0.99))
            .textRenderer(DSHologramTextRenderer(tint: tint, glowColor: glowColor))
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
        if isElevated {
            glyph
                .shadow(color: glowColor.opacity(0.58), radius: 3.2)
                .shadow(color: .black.opacity(0.24), radius: 0.7, y: 0.8)
                .accessibilityHidden(true)
        } else {
            glyph
                .accessibilityHidden(true)
        }
    }

    private var glyph: some View {
        ZStack {
            DSHologramBookmarkShape()
                .stroke(tint.opacity(0.99), style: glyphStrokeStyle)
            DSHologramStarShape()
                .fill(tint.opacity(0.99))
                .frame(width: size * 0.34, height: size * 0.34)
                .offset(y: -size * 0.15)
        }
        .padding(size * 0.04)
        .frame(width: size, height: size)
        .foregroundStyle(tint.opacity(0.99))
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
        var depthEdge = context
        depthEdge.addFilter(
            .shadow(
                color: .black.opacity(0.28),
                radius: 0.8,
                y: 0.65,
                options: .shadowOnly
            ),
            options: .linearColor
        )
        draw(layout, in: &depthEdge)

        var glow = context
        glow.opacity = 0.52
        glow.addFilter(
            .shadow(
                color: glowColor.opacity(0.68),
                radius: 3.1,
                options: .shadowOnly
            ),
            options: .linearColor
        )
        draw(layout, in: &glow)

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

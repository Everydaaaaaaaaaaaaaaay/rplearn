import SwiftUI

/// 旅行工作台功能场景。每个功能页使用与任务语义对应的独立摄影底图。
public enum DSWorkbenchSceneFocus: Sendable, Equatable {
    case learning
    case favorites
    case settings
    case account
    case archive

    fileprivate var assetName: String {
        switch self {
        case .learning: "detail_placement_learning_desk"
        case .favorites: "detail_favorites_journal"
        case .settings: "detail_settings_studio"
        case .account: "detail_account_sync_desk"
        case .archive: "detail_memory_archive_desk"
        }
    }

    fileprivate var scale: CGFloat {
        switch self {
        case .learning, .favorites, .settings, .account, .archive: 1
        }
    }

    fileprivate var anchor: UnitPoint {
        switch self {
        case .learning, .favorites, .settings, .account, .archive: .center
        }
    }
}

/// 二级页的摄影底图。只在布局时缩放一张静态图片，不做逐帧模糊或视差。
public struct DSWorkbenchBackdrop: View {
    private let focus: DSWorkbenchSceneFocus

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(focus: DSWorkbenchSceneFocus) {
        self.focus = focus
    }

    public var body: some View {
        GeometryReader { proxy in
            Image(focus.assetName, bundle: .main)
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .scaleEffect(focus.scale, anchor: focus.anchor)
                .clipped()
                .overlay { backdropWash }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var backdropWash: some View {
        if colorScheme == .dark {
            Color.black.opacity(reduceTransparency ? 0.34 : 0.24)
        }
    }
}

/// 功能页只使用三种材料重量，避免每一行都变成独立胶囊。
public enum DSWorkbenchPanelWeight: Sendable, Equatable {
    case chrome
    case content
    case reading
}

public struct DSWorkbenchPanel<Content: View>: View {
    private let weight: DSWorkbenchPanelWeight
    private let radius: CGFloat
    private let padding: CGFloat
    private let content: Content

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(
        weight: DSWorkbenchPanelWeight = .content,
        radius: CGFloat = DSRadius.hero,
        padding: CGFloat = DSSpacing.lg,
        @ViewBuilder content: () -> Content
    ) {
        self.weight = weight
        self.radius = radius
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        decorated(
            Group {
                if reduceTransparency {
                    content
                        .padding(padding)
                        .background(Color.dsSurface.opacity(0.985), in: shape)
                } else if #available(iOS 26.0, *) {
                    content
                        .padding(padding)
                        .background(panelTint, in: shape)
                        .glassEffect(.clear.tint(glassTint), in: shape)
                } else {
                    content
                        .padding(padding)
                        .background(.regularMaterial, in: shape)
                        .background(panelTint, in: shape)
                }
            },
            shape: shape
        )
    }

    private func decorated<Panel: View>(
        _ panel: Panel,
        shape: RoundedRectangle
    ) -> some View {
        panel
            .overlay {
                shape.stroke(borderColor, lineWidth: colorSchemeContrast == .increased ? 1.2 : 0.8)
            }
            .shadow(
                color: Color.black.opacity(shadowOpacity),
                radius: weight == .reading ? 22 : 14,
                y: weight == .reading ? 10 : 6
            )
    }

    private var panelTint: Color {
        if colorSchemeContrast == .increased { return Color.dsSurface.opacity(0.92) }
        switch weight {
        case .chrome:
            return Color.dsBrandCream.opacity(colorScheme == .dark ? 0.36 : 0.42)
        case .content:
            return Color.dsBrandCream.opacity(colorScheme == .dark ? 0.62 : 0.68)
        case .reading:
            return Color.dsBrandCream.opacity(colorScheme == .dark ? 0.78 : 0.82)
        }
    }

    private var glassTint: Color {
        switch weight {
        case .chrome: Color.dsBrandCream.opacity(0.08)
        case .content: Color.dsBrandCream.opacity(0.13)
        case .reading: Color.dsBrandCream.opacity(0.18)
        }
    }

    private var borderColor: Color {
        if colorSchemeContrast == .increased {
            return Color.dsSceneTextPrimary.opacity(0.34)
        }
        return colorScheme == .dark
            ? Color.white.opacity(0.16)
            : Color.white.opacity(0.76)
    }

    private var shadowOpacity: Double {
        switch weight {
        case .chrome: colorScheme == .dark ? 0.20 : 0.08
        case .content: colorScheme == .dark ? 0.27 : 0.12
        case .reading: colorScheme == .dark ? 0.32 : 0.15
        }
    }
}

/// 高保真稿中的连续纸张界面：不使用 Liquid Glass，也不叠加系统材质。
public struct DSWorkbenchPaperSheet<Content: View>: View {
    private let radius: CGFloat
    private let padding: CGFloat
    private let content: Content

    public init(
        radius: CGFloat = 26,
        padding: CGFloat = DSSpacing.lg,
        @ViewBuilder content: () -> Content
    ) {
        self.radius = radius
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        content
            .padding(padding)
            .background {
                shape
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.985, green: 0.970, blue: 0.925),
                                Color(red: 0.958, green: 0.935, blue: 0.878),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        shape.fill(
                            RadialGradient(
                                colors: [Color.white.opacity(0.30), .clear],
                                center: .topLeading,
                                startRadius: 10,
                                endRadius: 360
                            )
                        )
                    }
            }
            .overlay {
                shape.stroke(Color.white.opacity(0.78), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.13), radius: 18, y: 9)
    }
}

/// 皮革包边的黑曜石圆章与浮金线条图标。
/// 静态渐变、刻纹与多层位移共同建立 2.5D 深度，不引入逐帧特效。
public struct DSObsidianMedallion: View {
    private let systemImage: String
    private let size: CGFloat

    public init(systemImage: String, size: CGFloat = 64) {
        self.systemImage = systemImage
        self.size = size
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.50))
                .offset(y: size * 0.055)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.16, green: 0.24, blue: 0.30),
                            Color(red: 0.055, green: 0.105, blue: 0.145),
                            Color(red: 0.012, green: 0.030, blue: 0.046),
                        ],
                        center: UnitPoint(x: 0.32, y: 0.24),
                        startRadius: 1,
                        endRadius: size * 0.82
                    )
                )
                .overlay {
                    Circle()
                        .fill(
                            AngularGradient(
                                colors: [
                                    .white.opacity(0.13),
                                    .clear,
                                    .black.opacity(0.22),
                                    .clear,
                                    .white.opacity(0.08),
                                ],
                                center: .center
                            )
                        )
                        .blendMode(.screen)
                }
                .overlay { ObsidianMicrotexture().padding(size * 0.055) }
                .overlay {
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.dsFoilGold.opacity(0.66),
                                    Color.white.opacity(0.32),
                                    Color.black.opacity(0.68),
                                    Color.dsFoilGold.opacity(0.30),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: max(1, size * 0.022)
                        )
                }
                .overlay {
                    Circle()
                        .inset(by: size * 0.09)
                        .stroke(Color.white.opacity(0.11), lineWidth: 0.75)
                }
                .overlay {
                    Circle()
                        .trim(from: 0.58, to: 0.89)
                        .stroke(
                            Color.dsFoilGold.opacity(0.32),
                            style: StrokeStyle(lineWidth: 1.1, lineCap: .round)
                        )
                        .rotationEffect(.degrees(7))
                        .padding(size * 0.055)
                }

            Image(systemName: systemImage)
                .font(.system(size: size * 0.39, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(Color.black.opacity(0.72))
                .offset(x: size * 0.013, y: size * 0.043)

            Image(systemName: systemImage)
                .font(.system(size: size * 0.39, weight: .medium))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.94, blue: 0.67),
                            Color.dsFoilGold,
                            Color(red: 0.65, green: 0.39, blue: 0.11),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color.dsFoilGold.opacity(0.60), radius: 2.2)
                .shadow(color: Color.dsFoilGold.opacity(0.24), radius: 7)
                .overlay {
                    Image(systemName: systemImage)
                        .font(.system(size: size * 0.39, weight: .thin))
                        .foregroundStyle(Color.white.opacity(0.46))
                        .offset(x: -0.35, y: -0.55)
                }
        }
        .frame(width: size, height: size)
        .drawingGroup(opaque: false, colorMode: .linear)
        .shadow(color: Color.dsFoilGold.opacity(0.16), radius: 7)
        .shadow(color: Color.black.opacity(0.30), radius: 9, y: 6)
        .accessibilityHidden(true)
    }
}

private struct ObsidianMicrotexture: View {
    var body: some View {
        Canvas { context, canvasSize in
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let minimum = min(canvasSize.width, canvasSize.height)

            for index in 0 ..< 15 {
                let radius = minimum * (0.20 + CGFloat(index) * 0.0205)
                let start = Angle.degrees(Double(index * 23 + 196))
                let end = Angle.degrees(Double(index * 23 + 232))
                var arc = Path()
                arc.addArc(
                    center: center,
                    radius: radius,
                    startAngle: start,
                    endAngle: end,
                    clockwise: false
                )
                context.stroke(
                    arc,
                    with: .color(.white.opacity(index.isMultiple(of: 3) ? 0.075 : 0.035)),
                    lineWidth: 0.55
                )
            }

            for index in 0 ..< 11 {
                let y = minimum * (0.16 + CGFloat(index) * 0.063)
                var grain = Path()
                grain.move(to: CGPoint(x: minimum * 0.17, y: y))
                grain.addCurve(
                    to: CGPoint(x: minimum * 0.83, y: y + CGFloat(index % 3 - 1) * 1.2),
                    control1: CGPoint(x: minimum * 0.36, y: y - 1.1),
                    control2: CGPoint(x: minimum * 0.62, y: y + 1.4)
                )
                context.stroke(
                    grain,
                    with: .color(.black.opacity(0.075)),
                    lineWidth: 0.45
                )
            }
        }
        .clipShape(Circle())
        .blendMode(.softLight)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 与工作台皮革物件一致的主操作，不使用大面积亮蓝。
public struct DSWorkbenchActionButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Color.dsTravelNavy, in: RoundedRectangle(cornerRadius: DSRadius.inline, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DSRadius.inline, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
            }
            .shadow(
                color: Color.dsTravelNavy.opacity(configuration.isPressed ? 0.12 : 0.24),
                radius: configuration.isPressed ? 3 : 10,
                y: configuration.isPressed ? 1 : 5
            )
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.982)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(reduceMotion ? nil : DSAnimation.feedback, value: configuration.isPressed)
    }
}

public extension ButtonStyle where Self == DSWorkbenchActionButtonStyle {
    static var dsWorkbenchAction: DSWorkbenchActionButtonStyle {
        DSWorkbenchActionButtonStyle()
    }
}

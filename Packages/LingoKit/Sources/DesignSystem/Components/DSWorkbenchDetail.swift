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
                .interpolation(.high)
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
        let faceSize = size * 0.88

        ZStack {
            // 后层略向下露出，形成完整而未被裁切的石章厚度。
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.13, green: 0.17, blue: 0.19),
                            Color(red: 0.015, green: 0.022, blue: 0.026),
                            .black,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: faceSize, height: faceSize)
                .overlay {
                    Circle()
                        .stroke(Color.black.opacity(0.78), lineWidth: max(1.4, size * 0.026))
                }
                .offset(y: size * 0.052)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.23, green: 0.29, blue: 0.31),
                            Color(red: 0.075, green: 0.11, blue: 0.125),
                            Color(red: 0.014, green: 0.026, blue: 0.033),
                            Color.black,
                        ],
                        center: UnitPoint(x: 0.29, y: 0.21),
                        startRadius: 1,
                        endRadius: faceSize * 0.76
                    )
                )
                .frame(width: faceSize, height: faceSize)
                .overlay {
                    Circle()
                        .fill(
                            AngularGradient(
                                colors: [
                                    .white.opacity(0.17),
                                    .clear,
                                    .black.opacity(0.30),
                                    .clear,
                                    Color(red: 0.42, green: 0.56, blue: 0.60).opacity(0.12),
                                    .clear,
                                ],
                                center: .center
                            )
                        )
                        .padding(max(1, faceSize * 0.025))
                        .blendMode(.softLight)
                }
                .overlay {
                    ObsidianFlowTexture()
                        .padding(faceSize * 0.065)
                }
                .overlay {
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.dsFoilGold.opacity(0.56),
                                    Color.white.opacity(0.46),
                                    Color(red: 0.10, green: 0.15, blue: 0.17),
                                    Color.black.opacity(0.88),
                                    Color.dsFoilGold.opacity(0.28),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: max(1.5, size * 0.026)
                        )
                }
                .overlay {
                    Circle()
                        .inset(by: faceSize * 0.085)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.24),
                                    Color.white.opacity(0.04),
                                    Color.black.opacity(0.56),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: max(0.8, size * 0.012)
                        )
                }
                .overlay {
                    Circle()
                        .trim(from: 0.54, to: 0.88)
                        .stroke(
                            Color.dsFoilGold.opacity(0.38),
                            style: StrokeStyle(
                                lineWidth: max(0.9, size * 0.015),
                                lineCap: .round
                            )
                        )
                        .rotationEffect(.degrees(9))
                        .padding(faceSize * 0.045)
                }
                .offset(y: -size * 0.012)

            Image(systemName: systemImage)
                .font(.system(size: size * 0.39, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(Color.black.opacity(0.80))
                .offset(x: size * 0.014, y: size * 0.050)

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
        .shadow(color: Color.dsFoilGold.opacity(0.16), radius: 7)
        .shadow(color: Color.black.opacity(0.34), radius: 9, y: 5)
        .accessibilityHidden(true)
    }
}

private struct ObsidianFlowTexture: View {
    var body: some View {
        Canvas { context, canvasSize in
            let width = canvasSize.width
            let height = canvasSize.height

            // 黑曜石冷却形成的平行流纹：数量少、方向统一，避免噪点式假材质。
            for index in 0 ..< 9 {
                let row = CGFloat(index)
                let y = height * (0.14 + row * 0.087)
                let bend = CGFloat(index % 3 - 1) * height * 0.022
                var vein = Path()
                vein.move(to: CGPoint(x: width * 0.05, y: y + bend))
                vein.addCurve(
                    to: CGPoint(x: width * 0.95, y: y - bend * 0.4),
                    control1: CGPoint(x: width * 0.30, y: y - height * 0.065 - bend),
                    control2: CGPoint(x: width * 0.68, y: y + height * 0.060 + bend)
                )
                context.stroke(
                    vein,
                    with: .color(
                        Color(red: 0.63, green: 0.73, blue: 0.76)
                            .opacity(index.isMultiple(of: 3) ? 0.22 : 0.115)
                    ),
                    lineWidth: index.isMultiple(of: 3) ? 0.95 : 0.58
                )
            }

            // 深色带与亮纹保持同一流向，形成天然玻璃质熔流，不制造规则交叉网格。
            for index in 0 ..< 4 {
                let row = CGFloat(index)
                let y = height * (0.22 + row * 0.18)
                var mineralBand = Path()
                mineralBand.move(to: CGPoint(x: width * 0.08, y: y))
                mineralBand.addCurve(
                    to: CGPoint(x: width * 0.92, y: y + height * 0.025),
                    control1: CGPoint(x: width * 0.31, y: y + height * 0.072),
                    control2: CGPoint(x: width * 0.67, y: y - height * 0.062)
                )
                context.stroke(
                    mineralBand,
                    with: .color(.black.opacity(0.24)),
                    lineWidth: index.isMultiple(of: 2) ? 1.05 : 0.72
                )
            }
        }
        .clipShape(Circle())
        .blendMode(.screen)
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

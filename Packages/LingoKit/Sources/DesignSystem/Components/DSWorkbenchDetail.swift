import SwiftUI

/// “我的”页旅行工作台的功能区域。所有二级页复用同一张原图，避免物件外观漂移。
public enum DSWorkbenchSceneFocus: Sendable, Equatable {
    case learning
    case favorites
    case settings
    case account
    case archive

    fileprivate var scale: CGFloat {
        switch self {
        case .learning: 1.06
        case .favorites: 1.12
        case .settings: 1.10
        case .account: 1.08
        case .archive: 1.12
        }
    }

    fileprivate var anchor: UnitPoint {
        switch self {
        case .learning: UnitPoint(x: 0.54, y: 0.52)
        case .favorites: UnitPoint(x: 0.14, y: 0.59)
        case .settings: UnitPoint(x: 0.82, y: 0.61)
        case .account: UnitPoint(x: 0.52, y: 0.66)
        case .archive: UnitPoint(x: 0.54, y: 0.12)
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
            Image("profile_modern_travel_desk_interactive_scene", bundle: .main)
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .scaleEffect(focus.scale, anchor: focus.anchor)
                .clipped()
                .overlay { atmosphericWash }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var atmosphericWash: some View {
        ZStack {
            Color.black.opacity(colorScheme == .dark ? 0.30 : 0.025)

            LinearGradient(
                stops: [
                    .init(color: Color.dsBrandCream.opacity(topCreamOpacity), location: 0),
                    .init(color: Color.clear, location: 0.38),
                    .init(color: Color.dsTravelNavy.opacity(bottomNavyOpacity), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var topCreamOpacity: Double {
        if reduceTransparency { return colorScheme == .dark ? 0.20 : 0.34 }
        return colorScheme == .dark ? 0.08 : 0.16
    }

    private var bottomNavyOpacity: Double {
        if reduceTransparency { return colorScheme == .dark ? 0.30 : 0.16 }
        return colorScheme == .dark ? 0.18 : 0.07
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

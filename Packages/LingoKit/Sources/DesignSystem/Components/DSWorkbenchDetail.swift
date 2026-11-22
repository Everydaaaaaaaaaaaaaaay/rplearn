import SwiftUI

/// 旅行工作台功能场景。蓬蓬设计后各功能页统一用白底，不再铺摄影底图；保留枚举供原调用点使用。
public enum DSWorkbenchSceneFocus: Sendable, Equatable {
    case learning
    case favorites
    case settings
    case account
    case archive
    case profile
    case subscription
}

/// 二级页背景：蓬蓬白底（深色为夜空蓝），代替原来的工作台实景照片。
public struct DSWorkbenchBackdrop: View {
    private let focus: DSWorkbenchSceneFocus

    public init(focus: DSWorkbenchSceneFocus) {
        self.focus = focus
    }

    public var body: some View {
        PuffPageBackdrop()
            .environment(\.puffPageTint, .sky)
    }
}

/// 功能页只使用三种材料重量，避免每一行都变成独立胶囊。
public enum DSWorkbenchPanelWeight: Sendable, Equatable {
    case chrome
    case content
    case reading
}

/// 功能页面板：蓬蓬厚卡片。
public struct DSWorkbenchPanel<Content: View>: View {
    private let weight: DSWorkbenchPanelWeight
    private let radius: CGFloat
    private let padding: CGFloat
    private let content: Content

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
        content
            .padding(padding)
            .puffCard(radius: min(radius, Puff.Radius.huge))
    }
}

/// 连续纸张界面：蓬蓬厚卡片。
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
        content
            .padding(padding)
            .puffCard(radius: min(radius, Puff.Radius.huge))
    }
}

/// 圆形图标章：糖果色浅底圆 + 深色图标。
public struct DSObsidianMedallion: View {
    private let systemImage: String
    private let size: CGFloat
    private let isRaised: Bool

    public init(systemImage: String, size: CGFloat = 64, isRaised: Bool = true) {
        self.systemImage = systemImage
        self.size = size
        self.isRaised = isRaised
    }

    public var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.4, weight: Puff.Weight.icon, design: .rounded))
            .foregroundStyle(PuffCandy.sky.deep)
            .frame(width: size, height: size)
            .background(PuffCandy.sky.wash, in: Circle())
            .overlay { Circle().strokeBorder(Puff.Palette.card, lineWidth: max(2, size * 0.05)) }
            .padding(.bottom, isRaised ? 3 : 0)
            .background(alignment: .bottom) {
                if isRaised {
                    Circle().fill(PuffCandy.sky.base.opacity(0.35)).frame(width: size, height: size)
                }
            }
            .accessibilityHidden(true)
    }
}

/// 功能页主操作：实心糖果按钮，按下陷进唇边。
public struct DSWorkbenchActionButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.puff(.headline, Puff.Weight.emphasis))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 52)
            .modifier(PuffChunkyBackground(
                radius: Puff.Radius.medium, face: PuffCandy.sky.base, border: .clear,
                lip: PuffCandy.sky.lip, lipHeight: Puff.Lip.button, pressed: configuration.isPressed
            ))
            .opacity(isEnabled ? 1 : 0.5)
            .animation(reduceMotion ? nil : (configuration.isPressed ? Puff.Motion.press : Puff.Motion.jelly),
                       value: configuration.isPressed)
    }
}

public extension ButtonStyle where Self == DSWorkbenchActionButtonStyle {
    static var dsWorkbenchAction: DSWorkbenchActionButtonStyle {
        DSWorkbenchActionButtonStyle()
    }
}

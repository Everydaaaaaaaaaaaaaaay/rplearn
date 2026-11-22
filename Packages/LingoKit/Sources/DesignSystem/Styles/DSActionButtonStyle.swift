import SwiftUI

/// 场景化界面的统一操作按钮：单层、清晰、克制，保留 SwiftUI Button 的原生行为。
public struct DSActionButtonStyle: ButtonStyle {
    public enum Variant: Sendable {
        case primary
        case tinted(Color)
        case secondary
        case glass
        case destructive
    }

    private let variant: Variant
    private let fullWidth: Bool
    private let compact: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(variant: Variant = .primary, fullWidth: Bool = true, compact: Bool = false) {
        self.variant = variant
        self.fullWidth = fullWidth
        self.compact = compact
    }

    @Environment(\.isEnabled) private var isEnabled

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.puff(compact ? .subheadline : .headline, Puff.Weight.emphasis))
            .foregroundStyle(foreground)
            .padding(.horizontal, compact ? 14 : 18)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(minHeight: compact ? 38 : 50)
            .modifier(PuffChunkyBackground(
                radius: compact ? Puff.Radius.small : Puff.Radius.medium,
                face: face, border: border, lip: lip,
                lipHeight: compact ? Puff.Lip.chip : Puff.Lip.button,
                pressed: configuration.isPressed
            ))
            .opacity(isEnabled ? 1 : 0.5)
            .animation(reduceMotion ? nil : (configuration.isPressed ? Puff.Motion.press : Puff.Motion.release),
                       value: configuration.isPressed)
    }

    /// 蓬蓬配色：实心糖果按钮带深色唇边，次要按钮是带描边的白卡片。
    private var face: Color {
        switch variant {
        case .primary: PuffCandy.sky.base
        case .tinted(let color): color
        case .secondary: Puff.Palette.card
        case .glass: .white.opacity(0.18)
        case .destructive: Puff.Palette.cherry
        }
    }

    private var lip: Color {
        switch variant {
        case .primary: PuffCandy.sky.lip
        case .tinted(let color): color.mix(with: .black, by: 0.22)
        case .secondary: Puff.Palette.lip
        case .glass: .clear
        case .destructive: Puff.Palette.cherry.mix(with: .black, by: 0.22)
        }
    }

    private var foreground: Color {
        switch variant {
        case .primary, .tinted, .destructive, .glass: .white
        case .secondary: Puff.Palette.ink
        }
    }

    private var border: Color {
        switch variant {
        case .secondary: Puff.Palette.line
        case .glass: .white.opacity(0.34)
        default: .clear
        }
    }
}

public extension ButtonStyle where Self == DSActionButtonStyle {
    static var dsActionPrimary: DSActionButtonStyle { DSActionButtonStyle() }

    static func dsAction(
        _ variant: DSActionButtonStyle.Variant,
        fullWidth: Bool = true,
        compact: Bool = false
    ) -> DSActionButtonStyle {
        DSActionButtonStyle(variant: variant, fullWidth: fullWidth, compact: compact)
    }
}

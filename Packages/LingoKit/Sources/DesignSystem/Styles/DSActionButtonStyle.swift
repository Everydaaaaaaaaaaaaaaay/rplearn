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
    @Environment(\.isEnabled) private var enabled

    public init(variant: Variant = .primary, fullWidth: Bool = true, compact: Bool = false) {
        self.variant = variant
        self.fullWidth = fullWidth
        self.compact = compact
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(compact ? .subheadline : .body, design: .default, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, compact ? 14 : 18)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(minHeight: compact ? 44 : 50)
            .background {
                RoundedRectangle(cornerRadius: DSRadius.inline, style: .continuous)
                    .fill(fill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: DSRadius.inline, style: .continuous)
                    .stroke(border, lineWidth: borderWidth)
            }
            .shadow(
                color: shadow,
                radius: configuration.isPressed ? 2 : 8,
                y: configuration.isPressed ? 1 : 3
            )
            .scaleEffect(1)
            .opacity(!enabled ? 0.4 : configuration.isPressed ? 0.65 : 1)
            .animation(reduceMotion ? nil : DSAnimation.feedback, value: configuration.isPressed)
    }

    private var fill: Color {
        switch variant {
        case .primary: DSReadingPalette.primary
        case .tinted(let color): color == .dsSky || color == .dsSkyDeep ? DSReadingPalette.primary : color
        case .secondary: .dsSurfaceMuted
        case .glass: .white.opacity(0.14)
        case .destructive: .dsDanger
        }
    }

    private var foreground: Color {
        switch variant {
        case .primary: DSReadingPalette.onPrimary
        case .tinted(let color): color == .dsSky || color == .dsSkyDeep ? DSReadingPalette.onPrimary : .white
        case .destructive: .white
        case .secondary: DSReadingPalette.ink
        case .glass: .white
        }
    }

    private var border: Color {
        switch variant {
        case .secondary: .dsBorder
        case .glass: .white.opacity(0.34)
        default: .white.opacity(0.12)
        }
    }

    private var borderWidth: CGFloat {
        switch variant {
        case .secondary, .glass: 1
        default: 0.5
        }
    }

    private var shadow: Color {
        switch variant {
        case .primary: .clear
        case .tinted(let color): color == .dsSky || color == .dsSkyDeep ? DSReadingPalette.primary : color.opacity(0.18)
        case .destructive: Color.dsDanger.opacity(0.18)
        case .secondary: .black.opacity(0.035)
        case .glass: .black.opacity(0.08)
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

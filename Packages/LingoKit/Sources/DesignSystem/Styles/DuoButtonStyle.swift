import SwiftUI

public struct DuoButtonStyle: ButtonStyle {
    public enum Variant: Sendable {
        case primary
        case success
        case tinted(Color)
        case outline
    }

    private let variant: Variant
    private let fullWidth: Bool
    private let compact: Bool

    public init(variant: Variant = .primary, fullWidth: Bool = true, compact: Bool = false) {
        self.variant = variant
        self.fullWidth = fullWidth
        self.compact = compact
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded, weight: .bold))
            .foregroundStyle(foreground)
            .padding(.horizontal, compact ? 14 : 18)
            .padding(.vertical, compact ? 9 : 13)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background {
                RoundedRectangle(cornerRadius: DSRadius.inline, style: .continuous)
                    .fill(bottom)
                    .offset(y: 4)
            }
            .background {
                RoundedRectangle(cornerRadius: DSRadius.inline, style: .continuous)
                    .fill(face)
                    .overlay {
                        if isOutline {
                            RoundedRectangle(cornerRadius: DSRadius.inline, style: .continuous)
                                .stroke(Color.dsSky, lineWidth: 2)
                        }
                    }
            }
            .offset(y: configuration.isPressed ? 4 : 0)
            .animation(DSAnimation.press, value: configuration.isPressed)
    }

    private var isOutline: Bool {
        if case .outline = variant { true } else { false }
    }

    private var face: Color {
        switch variant {
        case .primary: .dsSky
        case .success: .dsSuccess
        case .tinted(let color): color
        case .outline: .dsSurface
        }
    }

    private var bottom: Color {
        switch variant {
        case .primary: .dsSkyDeep
        case .success: .dsSuccess.opacity(0.7)
        case .tinted(let color): color.opacity(0.72)
        case .outline: .dsSky.opacity(0.36)
        }
    }

    private var foreground: Color {
        isOutline ? .dsSky : .white
    }
}

public extension ButtonStyle where Self == DuoButtonStyle {
    static var duoPrimary: DuoButtonStyle { DuoButtonStyle() }

    static func duo(
        _ variant: DuoButtonStyle.Variant,
        fullWidth: Bool = true,
        compact: Bool = false
    ) -> DuoButtonStyle {
        DuoButtonStyle(variant: variant, fullWidth: fullWidth, compact: compact)
    }
}

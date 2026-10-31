import SwiftUI

/// 表面只负责层级，不替业务内容决定布局或美术。
public enum DSSurfaceLevel: Sendable, Equatable {
    /// 同一页面内的信息分组：描边分隔，不制造悬浮感。
    case grouped
    /// 置于页面背景上的独立内容：轻微抬升。
    case elevated
    /// 置于场景美术上的短暂或关键内容：更清晰的空间层级。
    case floating
}

private struct DSSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let level: DSSurfaceLevel
    let padding: CGFloat
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.dsSurface)
                    .shadow(color: shadowColor, radius: shadowRadius, y: shadowY)
            )
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            }
    }

    private var shadowColor: Color {
        guard level != .grouped else { return .clear }
        if colorScheme == .dark {
            return .black.opacity(level == .floating ? 0.34 : 0.2)
        }
        return .black.opacity(level == .floating ? 0.13 : 0.055)
    }

    private var shadowRadius: CGFloat {
        switch level {
        case .grouped: 0
        case .elevated: 10
        case .floating: 18
        }
    }

    private var shadowY: CGFloat {
        switch level {
        case .grouped: 0
        case .elevated: 4
        case .floating: 8
        }
    }

    private var borderColor: Color {
        switch level {
        case .grouped, .elevated:
            Color.dsBorder
        case .floating:
            colorScheme == .dark ? .white.opacity(0.14) : .white.opacity(0.82)
        }
    }
}

public extension View {
    func dsSurface(
        _ level: DSSurfaceLevel = .grouped,
        padding: CGFloat = DSSpacing.md,
        radius: CGFloat = DSRadius.card
    ) -> some View {
        modifier(DSSurfaceModifier(level: level, padding: padding, radius: radius))
    }
}

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

/// 旧表面统一为蓬蓬厚卡片：分组与独立内容都用白色正面、细描边和底部唇边。
private struct DSSurfaceModifier: ViewModifier {
    let level: DSSurfaceLevel
    let padding: CGFloat
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .puffCard(radius: min(max(radius, Puff.Radius.medium), Puff.Radius.huge),
                      lipHeight: level == .grouped ? 0 : Puff.Lip.card)
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

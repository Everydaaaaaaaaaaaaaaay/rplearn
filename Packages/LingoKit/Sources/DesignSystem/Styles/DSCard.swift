import SwiftUI

private struct DSCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let padding: CGFloat
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.dsSurface)
                    .shadow(
                        color: colorScheme == .light ? .black.opacity(0.05) : .clear,
                        radius: 8,
                        y: 2
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.dsBorder, lineWidth: colorScheme == .dark ? 1 : 0.7)
            }
    }
}

public extension View {
    func dsCard(padding: CGFloat = DSSpacing.md, radius: CGFloat = DSRadius.card) -> some View {
        modifier(DSCardModifier(padding: padding, radius: radius))
    }
}

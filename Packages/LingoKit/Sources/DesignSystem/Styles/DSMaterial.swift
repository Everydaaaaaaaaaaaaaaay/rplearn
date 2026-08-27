import SwiftUI

private struct DSAdaptiveMaterialModifier<Background: Shape>: ViewModifier {
    let material: Material
    let shape: Background

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content.background(
            reduceTransparency
                ? AnyShapeStyle(Color.dsSurface)
                : AnyShapeStyle(material),
            in: shape
        )
    }
}

public extension View {
    /// 品牌材质层；开启“降低透明度”时自动降级为不透明 surface。
    func dsMaterial<Background: Shape>(
        _ material: Material = .ultraThinMaterial,
        in shape: Background
    ) -> some View {
        modifier(DSAdaptiveMaterialModifier(material: material, shape: shape))
    }

    /// 城市场景上的信息容器。iOS 26 使用原生 Liquid Glass，旧系统回退到材质模糊。
    func dsSceneGlass(
        radius: CGFloat = DSRadius.hero,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        modifier(
            DSSceneGlassModifier(
                radius: radius,
                tint: tint,
                interactive: interactive
            )
        )
    }

    /// iOS 26 将搜索保持为紧凑工具栏按钮；旧系统沿用系统默认搜索表现。
    @ViewBuilder
    func dsCompactSearchToolbar() -> some View {
        if #available(iOS 26.0, *) {
            searchToolbarBehavior(.minimize)
        } else {
            self
        }
    }
}

private struct DSSceneGlassModifier: ViewModifier {
    let radius: CGFloat
    let tint: Color?
    let interactive: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        if reduceTransparency {
            decorated(
                content.background(Color.dsSurface.opacity(0.97), in: shape),
                shape: shape
            )
        } else if #available(iOS 26.0, *) {
            decorated(
                content.glassEffect(
                    .regular.tint(tint).interactive(interactive),
                    in: shape
                ),
                shape: shape
            )
        } else {
            decorated(
                content.background(.regularMaterial, in: shape),
                shape: shape
            )
        }
    }

    private func decorated<ContentView: View, Background: Shape>(
        _ content: ContentView,
        shape: Background
    ) -> some View {
        content
            .overlay {
                shape.stroke(
                    colorScheme == .dark
                        ? Color.white.opacity(0.17)
                        : Color.white.opacity(0.6),
                    lineWidth: 0.8
                )
            }
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.24 : 0.12),
                radius: 18,
                y: 8
            )
    }
}

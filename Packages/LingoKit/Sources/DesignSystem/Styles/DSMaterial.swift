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
}

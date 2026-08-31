import SwiftUI

/// Controls how much of a photographed scene is allowed to show through a glass surface.
public enum DSSceneGlassLegibility: Sendable, Equatable {
    /// Keeps the glass as transparent as possible. Best for chrome and short labels.
    case ambient
    /// Adds a translucent surface behind content so long-form text keeps one stable contrast.
    case enhanced
    /// Uses a thicker neutral glass for large cards placed over detailed photography.
    case shielded
}

/// 将系统版本判断收敛到一处。调试构建可强制走旧系统分支，便于在只有
/// 新版 Simulator Runtime 的开发机上持续回归 iOS 18 材质与布局。
public enum DSPlatformVisualPolicy {
    public static var usesLiquidGlass: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["UI_TEST_FORCE_LEGACY_CHROME"] == "1" {
            return false
        }
        #endif
        if #available(iOS 26.0, *) {
            return true
        }
        return false
    }

    /// 当前已由 iPhone 13 / iOS 18 实机确认需要的渲染与安全区补偿。
    /// 不把它等同于“非液态玻璃”，避免未经复现就改动 iOS 19–25 的布局。
    public static var requiresIOS18RenderingCompensation: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["UI_TEST_FORCE_IOS18_COMPAT"] == "1" {
            return true
        }
        #endif
        return ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 18
    }
}

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
        interactive: Bool = false,
        legibility: DSSceneGlassLegibility = .ambient
    ) -> some View {
        modifier(
            DSSceneGlassModifier(
                radius: radius,
                tint: tint,
                interactive: interactive,
                legibility: legibility
            )
        )
    }

    /// iOS 26 将搜索保持为紧凑工具栏按钮；旧系统沿用系统默认搜索表现。
    @ViewBuilder
    func dsCompactSearchToolbar() -> some View {
        if #available(iOS 26.0, *), DSPlatformVisualPolicy.usesLiquidGlass {
            searchToolbarBehavior(.minimize)
        } else {
            self
        }
    }

    /// 摄影场景在 iOS 26 交给 Liquid Glass；旧系统由根视图安装明确的
    /// 胶囊材质，不能再让某个子页面把整个 UITabBar 背景清空。
    @ViewBuilder
    func dsSceneTabBarBackground() -> some View {
        if #available(iOS 26.0, *), DSPlatformVisualPolicy.usesLiquidGlass {
            toolbarBackground(.hidden, for: .tabBar)
        } else {
            self
        }
    }
}

private struct DSSceneGlassModifier: ViewModifier {
    let radius: CGFloat
    let tint: Color?
    let interactive: Bool
    let legibility: DSSceneGlassLegibility

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        if reduceTransparency {
            decorated(
                content.background(Color.dsSurface.opacity(0.97), in: shape),
                shape: shape
            )
        } else if #available(iOS 26.0, *), DSPlatformVisualPolicy.usesLiquidGlass {
            let glass: Glass = legibility == .ambient ? .regular : .clear
            decorated(
                legibilityBackground(content, in: shape)
                    .glassEffect(
                        glass.tint(tint).interactive(interactive),
                        in: shape
                    ),
                shape: shape
            )
        } else {
            decorated(
                legibilityBackground(content, in: shape)
                    .background(.regularMaterial, in: shape),
                shape: shape
            )
        }
    }

    @ViewBuilder
    private func legibilityBackground<ContentView: View, Background: Shape>(
        _ content: ContentView,
        in shape: Background
    ) -> some View {
        if legibility != .ambient {
            content.background(
                legibilitySurface.opacity(legibilitySurfaceOpacity),
                in: shape
            )
        } else {
            content
        }
    }

    private func decorated<ContentView: View, Background: Shape>(
        _ content: ContentView,
        shape: Background
    ) -> some View {
        content
            .overlay {
                shape.stroke(
                    borderColor,
                    lineWidth: 0.8
                )
            }
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.24 : 0.12),
                radius: 18,
                y: 8
            )
    }

    private var borderColor: Color {
        if legibility != .ambient {
            return Color.dsBrandInk.opacity(colorSchemeContrast == .increased ? 0.26 : 0.13)
        }
        return colorScheme == .dark
            ? Color.white.opacity(0.17)
            : Color.white.opacity(0.6)
    }

    private var legibilitySurface: Color {
        legibility == .shielded ? .dsSurfaceMuted : .dsSurface
    }

    private var legibilitySurfaceOpacity: Double {
        if colorSchemeContrast == .increased { return 0.88 }
        if legibility == .shielded {
            return colorScheme == .dark ? 0.54 : 0.44
        }
        return colorScheme == .dark ? 0.5 : 0.38
    }
}

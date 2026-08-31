import SwiftUI

/// 保留页面层级与状态、以短交叉淡入淡出替代横向 push 的轻量导航容器。
///
/// 适合 Tab 内部同一功能域的快速页面切换；每一层仍保留原生导航栏、返回按钮，
/// 并支持从屏幕左缘右滑返回。模态页面仍应继续使用 sheet/fullScreenCover。
public struct DSCrossfadeNavigationStack<Route: Hashable, Root: View, Destination: View>: View {
    @Binding private var path: [Route]
    private let title: (Route) -> String
    private let background: Color
    private let root: () -> Root
    private let destination: (Route) -> Destination

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        path: Binding<[Route]>,
        title: @escaping (Route) -> String,
        background: Color = .dsBackground,
        @ViewBuilder root: @escaping () -> Root,
        @ViewBuilder destination: @escaping (Route) -> Destination
    ) {
        _path = path
        self.title = title
        self.background = background
        self.root = root
        self.destination = destination
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                background
                    .ignoresSafeArea()
                    .accessibilityHidden(true)

                root()
                    .opacity(path.isEmpty ? 1 : 0)
                    .allowsHitTesting(path.isEmpty)
                    .accessibilityHidden(!path.isEmpty)
                    .zIndex(path.isEmpty ? 1 : 0)

                ForEach(Array(path.enumerated()), id: \.offset) { index, route in
                    let isTop = index == path.count - 1
                    destination(route)
                        .environment(\.dsCrossfadeNavigationManagesTitle, true)
                        .opacity(isTop ? 1 : 0)
                        .allowsHitTesting(isTop)
                        .accessibilityHidden(!isTop)
                        .zIndex(isTop ? 1 : 0)
                        .transition(.opacity)
                }
            }
            .animation(crossfadeAnimation, value: path)
            .navigationTitle(path.last.map(title) ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(path.isEmpty ? .hidden : .visible, for: .navigationBar)
            .toolbar {
                if !path.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: pop) {
                            Image(systemName: "chevron.backward")
                        }
                        .accessibilityLabel("返回")
                    }
                }
            }
            .overlay(alignment: .leading) {
                if !path.isEmpty {
                    Color.clear
                        .frame(width: 24)
                        .contentShape(Rectangle())
                        .gesture(edgeBackGesture)
                        .accessibilityHidden(true)
                }
            }
        }
        .background {
            background.ignoresSafeArea()
        }
    }

    private var crossfadeAnimation: Animation {
        reduceMotion ? DSAnimation.feedback : DSAnimation.snappy
    }

    private var edgeBackGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onEnded { value in
                guard value.translation.width >= 56,
                      abs(value.translation.height) <= value.translation.width * 0.75
                else { return }
                pop()
            }
    }

    private func pop() {
        guard !path.isEmpty else { return }
        _ = path.removeLast()
    }
}

private struct DSCrossfadeNavigationManagesTitleKey: EnvironmentKey {
    static let defaultValue = false
}

private extension EnvironmentValues {
    var dsCrossfadeNavigationManagesTitle: Bool {
        get { self[DSCrossfadeNavigationManagesTitleKey.self] }
        set { self[DSCrossfadeNavigationManagesTitleKey.self] = newValue }
    }
}

private struct DSNavigationTitleModifier: ViewModifier {
    let title: String
    @Environment(\.dsCrossfadeNavigationManagesTitle) private var isManagedByCrossfadeStack

    @ViewBuilder
    func body(content: Content) -> some View {
        if isManagedByCrossfadeStack {
            content
        } else {
            content.navigationTitle(title)
        }
    }
}

public extension View {
    /// 在普通 NavigationStack 中显示标题；在交叉淡入淡出导航中由容器统一管理。
    func dsNavigationTitle(_ title: String) -> some View {
        modifier(DSNavigationTitleModifier(title: title))
    }
}

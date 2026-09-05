import DesignSystem
import SwiftUI

/// Keeps photographic root scenes outside NavigationStack so navigation and
/// tab-bar safe-area updates do not feed back into their layout on iOS 18.
/// 首页与“我的”页复用同一交叉隐现和左缘返回手势。
struct SceneNavigationContainer<RootContent: View, DestinationContent: View>: View {
    let isPresentingDestination: Bool
    let navigationTitle: String
    let onBack: () -> Void
    let navigationPath: Binding<NavigationPath>?
    let rootContent: RootContent
    let destinationContent: DestinationContent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        isPresentingDestination: Bool,
        navigationTitle: String,
        onBack: @escaping () -> Void,
        navigationPath: Binding<NavigationPath>? = nil,
        @ViewBuilder root: () -> RootContent,
        @ViewBuilder destination: () -> DestinationContent
    ) {
        self.isPresentingDestination = isPresentingDestination
        self.navigationTitle = navigationTitle
        self.onBack = onBack
        self.navigationPath = navigationPath
        self.rootContent = root()
        self.destinationContent = destination()
    }

    var body: some View {
        ZStack {
            rootContent
                .opacity(isPresentingDestination ? 0 : 1)
                .allowsHitTesting(!isPresentingDestination)
                .accessibilityHidden(isPresentingDestination)
                .ignoresSafeArea(.container, edges: [.top, .bottom])
                .zIndex(0)

            if isPresentingDestination {
                destinationStack
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.dsBackground.ignoresSafeArea())
        .animation(contentAnimation, value: isPresentingDestination)
    }

    @ViewBuilder
    private var destinationStack: some View {
        if let navigationPath {
            NavigationStack(path: navigationPath) {
                destinationSurface
            }
        } else {
            NavigationStack {
                destinationSurface
            }
        }
    }

    private var destinationSurface: some View {
        ZStack(alignment: .leading) {
            destinationContent
                .transition(.opacity)

            Color.clear
                .frame(width: 28)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(backSwipeGesture)
                .accessibilityHidden(true)
                .zIndex(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.dsBackground.ignoresSafeArea())
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: onBack) {
                    Label("返回", systemImage: "chevron.left")
                }
            }
        }
    }

    /// The dedicated edge surface wins reliably over nested scroll views while
    /// still requiring a clear horizontal gesture from the leading edge.
    private var backSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onEnded { value in
                let horizontalDistance = value.translation.width
                let projectedDistance = value.predictedEndTranslation.width
                let verticalDistance = abs(value.translation.height)
                let startsAtLeadingEdge = value.startLocation.x <= 32
                let isClearlyHorizontal = horizontalDistance > verticalDistance * 1.25
                let passesDistanceThreshold = horizontalDistance >= 56 || projectedDistance >= 104

                guard startsAtLeadingEdge,
                      horizontalDistance > 0,
                      isClearlyHorizontal,
                      passesDistanceThreshold
                else { return }

                onBack()
            }
    }

    private var contentAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.10)
            : .easeInOut(duration: 0.18)
    }
}

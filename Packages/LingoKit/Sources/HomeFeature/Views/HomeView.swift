import DesignSystem
import DomainKit
import PersistenceKit
import SwiftUI

/// 首页聚合 Hub：用真实门厅物件承载世界地图、剧情和城市活动三个入口。
public struct HomeView: View {
    private let deps: HomeDependencies
    private let reloadToken: Int
    private let onInitialLoad: @MainActor () -> Void
    private let onOpenDestination: @MainActor (HomeDestination) -> Void

    @State private var profile: UserProfileDTO?
    @State private var completedStories: Set<String> = []
    @State private var touchedSceneEntry: HomeSceneEntryID?
    @StateObject private var sceneActions = DSSceneActionCoordinator<HomeSceneEntryID>()

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var sceneLayout: HomeDepartureSceneLayout {
        .forRegion(currentRegion?.id)
    }

    public init(
        deps: HomeDependencies,
        reloadToken: Int = 0,
        onInitialLoad: @escaping @MainActor () -> Void = {},
        onOpenDestination: @escaping @MainActor (HomeDestination) -> Void = { _ in }
    ) {
        self.deps = deps
        self.reloadToken = reloadToken
        self.onInitialLoad = onInitialLoad
        self.onOpenDestination = onOpenDestination
    }

    private var currentRegion: Region? {
        #if DEBUG
        if let requestedRegionID = ProcessInfo.processInfo.environment["UI_TEST_REGION"],
           let requestedRegion = deps.regionCatalog.region(id: requestedRegionID)
        {
            return requestedRegion
        }
        #endif
        return profile.flatMap { deps.regionCatalog.region(id: $0.currentRegionID) }
    }

    public var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibleContent
            } else {
                departureScene
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: reloadToken) { await reload() }
        .onDisappear(perform: sceneActions.cancel)
    }

    private var departureScene: some View {
        GeometryReader { proxy in
            let widthScale = proxy.size.width / HomeDepartureCanvas.width
            let placement = HomeDepartureCanvas.placement(in: proxy.size)
            let sceneScale = placement.scale
            let horizontalInset = placement.horizontalInset
            // 画布不足以覆盖视口时背景和 Metal 同步延伸；短屏先为底栏留空间，
            // 不再把底部可点击入口缩到标签栏后面。
            let canvasHeight = placement.height

            ZStack(alignment: .topLeading) {
                if sceneScale < widthScale {
                    compactHeightBackdrop(size: proxy.size)
                }

                departureCanvas(height: canvasHeight)
                    .frame(
                        width: HomeDepartureCanvas.width,
                        height: canvasHeight,
                        alignment: .topLeading
                    )
                    .dynamicTypeSize(...DynamicTypeSize.xLarge)
                    .scaleEffect(sceneScale, anchor: .topLeading)
                    .offset(x: horizontalInset)
            }
            .frame(
                width: proxy.size.width,
                height: proxy.size.height,
                alignment: .topLeading
            )
            .clipped()
        }
        .ignoresSafeArea(edges: [.top, .bottom])
        .dsSceneTabBarBackground()
    }

    private func compactHeightBackdrop(size: CGSize) -> some View {
        Image(sceneLayout.assetName, bundle: .main)
            .resizable()
            .scaledToFill()
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipped()
            .blur(radius: 5)
            .overlay(Color.black.opacity(colorScheme == .dark ? 0.26 : 0.04))
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }

    /// 背景、入口、光效和命中范围都在这张 402pt 参考画布中；运行时只整体缩放。
    private func departureCanvas(height: CGFloat) -> some View {
        let width = HomeDepartureCanvas.width
        let layout = sceneLayout

        return ZStack(alignment: .topLeading) {
            sceneBackground(width: width, height: height)

            HomeDepartureMetalView(
                layout: layout,
                flag: currentRegion.map { flag($0.countryCode) },
                cityName: currentRegion?.nameZh,
                storySubtitle: storySubtitle,
                pressedEntry: touchedSceneEntry ?? sceneActions.pressedHotspot,
                reduceMotion: reduceMotion
            )
            .frame(width: width, height: height)
            .accessibilityHidden(true)
            .allowsHitTesting(false)

            #if DEBUG
            if perspectiveDebugEnabled {
                HomePerspectiveDebugOverlay(layout: layout)
                    .frame(width: width, height: height)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }
            #endif

            if let currentRegion {
                HomeSceneHitTarget()
                .frame(width: layout.location.hitSize.width, height: layout.location.hitSize.height)
                .position(
                    x: width * layout.location.center.x,
                    y: height * layout.location.center.y
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("当前驻地，\(currentRegion.countryNameZh)，\(currentRegion.nameZh)")
            }

            Button {
                openSceneEntry(.map, destination: .map)
            } label: {
                HomePerspectiveHitTarget(
                    quad: layout.map.projectedRegion(size: layout.map.hitSize).photoQuad
                )
            }
            .buttonStyle(HomeScenePressReportingButtonStyle(entry: .map, pressedEntry: $touchedSceneEntry))
            .frame(width: width, height: height)
            .accessibilityLabel("世界地图")
            .accessibilityHint("查看城市并开始旅行")

            Button {
                openSceneEntry(.story, destination: .stories)
            } label: {
                HomePerspectiveHitTarget(
                    quad: layout.story.projectedRegion(size: layout.story.hitSize).photoQuad
                )
            }
            .buttonStyle(HomeScenePressReportingButtonStyle(entry: .story, pressedEntry: $touchedSceneEntry))
            .frame(width: width, height: height)
            .accessibilityLabel("剧情，\(storySubtitle)")
            .accessibilityHint("查看主线与当前城市剧情")

            Button {
                openSceneEntry(.activities, destination: .activities)
            } label: {
                HomePerspectiveHitTarget(
                    quad: layout.activities.projectedRegion(size: layout.activities.hitSize).photoQuad
                )
            }
            .buttonStyle(HomeScenePressReportingButtonStyle(entry: .activities, pressedEntry: $touchedSceneEntry))
            .frame(width: width, height: height)
            .accessibilityLabel("城市活动")
            .accessibilityHint("参加当地活动并认识旅途朋友")
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }

    private func sceneBackground(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Image(sceneLayout.assetName, bundle: .main)
                .resizable()
                .frame(width: width, height: height)

            Color.black.opacity(colorScheme == .dark ? 0.22 : 0.015)
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var accessibleContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                if let currentRegion {
                    Label(
                        "当前驻地：\(currentRegion.nameZh)",
                        systemImage: "location.fill"
                    )
                    .font(.title2.bold())
                    .accessibilityLabel("当前驻地，\(currentRegion.countryNameZh)，\(currentRegion.nameZh)")
                }

                accessibleLink(
                    entry: .map,
                    destination: .map,
                    title: "世界地图",
                    subtitle: "查看城市并开始旅行",
                    systemImage: "map"
                )
                accessibleLink(
                    entry: .story,
                    destination: .stories,
                    title: "剧情",
                    subtitle: storySubtitle,
                    systemImage: "waveform.path.ecg.rectangle"
                )
                accessibleLink(
                    entry: .activities,
                    destination: .activities,
                    title: "城市活动",
                    subtitle: "参加当地活动并认识旅途朋友",
                    systemImage: "figure.walk.motion"
                )
            }
            .padding(DSSpacing.md)
        }
        .refreshable { await reload() }
        .background(Color.dsBackground)
    }

    private func accessibleLink(
        entry: HomeSceneEntryID,
        destination: HomeDestination,
        title: String,
        subtitle: String,
        systemImage: String
    ) -> some View {
        Button {
            openSceneEntry(entry, destination: destination)
        } label: {
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .frame(width: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dsSurface(.elevated)
    }

    private func openSceneEntry(
        _ entry: HomeSceneEntryID,
        destination: HomeDestination
    ) {
        sceneActions.perform(for: entry) {
            onOpenDestination(destination)
        }
    }

    private var mainlineJourney: MainlineJourney {
        MainlineCatalog.journey(starterRegionID: profile?.starterRegionID)
    }

    private var storySubtitle: String {
        guard let nextStop = mainlineJourney.stops.first(where: {
            !completedStories.contains($0.chapter.storyID)
        }) else {
            return "五城回声 · 已完成"
        }
        let cityName = deps.regionCatalog.region(id: nextStop.regionID)?.nameZh ?? nextStop.chapter.title
        return "下一站 · \(cityName)"
    }

    private func reload() async {
        async let loadedProfile = try? deps.economyStore.profile()
        async let loadedCompleted = try? deps.storyProgress.completedStoryIDs()

        profile = await loadedProfile
        completedStories = await loadedCompleted ?? []
        onInitialLoad()
    }

    private func flag(_ countryCode: String) -> String {
        countryCode.uppercased().unicodeScalars.reduce(into: "") { result, scalar in
            if let value = Unicode.Scalar(0x1F1E6 + scalar.value - Unicode.Scalar("A").value) {
                result.unicodeScalars.append(value)
            }
        }
    }

    #if DEBUG
    private var perspectiveDebugEnabled: Bool {
        ProcessInfo.processInfo.environment["HOME_PERSPECTIVE_DEBUG"] == "1"
    }
    #endif
}

/// GPU 层只画视觉，透明 SwiftUI 入口继续提供原生导航、命中语义与即时按压状态。
private struct HomeSceneHitTarget: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.001))
            .contentShape(Rectangle())
    }
}

private struct HomePerspectiveHitTarget: View {
    let quad: HomePerspectiveQuad

    var body: some View {
        HomeNormalizedQuadShape(quad: quad)
            .fill(Color.white.opacity(0.001))
            .contentShape(HomeNormalizedQuadShape(quad: quad))
    }
}

private struct HomeNormalizedQuadShape: Shape {
    let quad: HomePerspectiveQuad

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: point(quad.topLeft, in: rect))
        path.addLine(to: point(quad.topRight, in: rect))
        path.addLine(to: point(quad.bottomRight, in: rect))
        path.addLine(to: point(quad.bottomLeft, in: rect))
        path.closeSubpath()
        return path
    }

    private func point(_ normalized: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + normalized.x * rect.width,
            y: rect.minY + normalized.y * rect.height
        )
    }
}

#if DEBUG
private struct HomePerspectiveDebugOverlay: View {
    let layout: HomeDepartureSceneLayout

    var body: some View {
        Canvas { context, size in
            drawSurface(layout.location.projectedRegion().surface, color: .yellow, context: &context, size: size)
            drawSurface(layout.map.projectedRegion().surface, color: .cyan, context: &context, size: size)
            drawSurface(layout.activities.projectedRegion().surface, color: .orange, context: &context, size: size)
            drawRegion(layout.location.projectedRegion(), color: .yellow, context: &context, size: size)
            drawRegion(layout.map.projectedRegion(), color: .cyan, context: &context, size: size)
            drawRegion(layout.story.projectedRegion(), color: .cyan, context: &context, size: size)
            drawRegion(layout.activities.projectedRegion(), color: .orange, context: &context, size: size)
        }
    }

    private func drawSurface(
        _ surface: HomePhotoSurface,
        color: Color,
        context: inout GraphicsContext,
        size: CGSize
    ) {
        let path = path(surface.quad, size: size)
        context.stroke(path, with: .color(color.opacity(0.92)), lineWidth: 1.2)
        let poseLabel = String(
            format: "%@  P %.0f°  Y %.0f°  R %.0f°",
            surface.pose.name,
            surface.pose.pitch,
            surface.pose.yaw,
            surface.pose.roll
        )
        let text = Text(poseLabel)
        .font(.system(size: 8, weight: .semibold, design: .rounded))
        .foregroundStyle(color)
        let label = context.resolve(text)
        let anchor = CGPoint(
            x: surface.quad.topLeft.x * size.width,
            y: surface.quad.topLeft.y * size.height - 7
        )
        context.draw(label, at: anchor, anchor: .bottomLeading)
    }

    private func drawRegion(
        _ region: HomeProjectedRegion,
        color: Color,
        context: inout GraphicsContext,
        size: CGSize
    ) {
        context.stroke(
            path(region.photoQuad, size: size),
            with: .color(color.opacity(0.78)),
            style: StrokeStyle(lineWidth: 0.8, dash: [3, 2])
        )
    }

    private func path(_ quad: HomePerspectiveQuad, size: CGSize) -> Path {
        var path = Path()
        let points = quad.points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
        guard let first = points.first else { return path }
        path.move(to: first)
        points.dropFirst().forEach { path.addLine(to: $0) }
        path.closeSubpath()
        return path
    }
}
#endif

private struct HomeScenePressReportingButtonStyle: ButtonStyle {
    let entry: HomeSceneEntryID
    @Binding var pressedEntry: HomeSceneEntryID?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    pressedEntry = entry
                } else if pressedEntry == entry {
                    pressedEntry = nil
                }
            }
    }
}

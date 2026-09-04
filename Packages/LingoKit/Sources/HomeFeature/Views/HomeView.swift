import DesignSystem
import DomainKit
import PersistenceKit
import SwiftUI

/// 首页聚合 Hub：用真实门厅物件承载世界地图、剧情和城市活动三个入口。
public struct HomeView: View {
    private let deps: HomeDependencies
    private let reloadToken: Int
    private let onInitialLoad: @MainActor () -> Void

    @State private var profile: UserProfileDTO?
    @State private var completedStories: Set<String> = []
    @State private var pressedSceneEntry: HomeSceneEntryID?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let sceneLayout = HomeDepartureSceneLayout.production

    public init(
        deps: HomeDependencies,
        reloadToken: Int = 0,
        onInitialLoad: @escaping @MainActor () -> Void = {}
    ) {
        self.deps = deps
        self.reloadToken = reloadToken
        self.onInitialLoad = onInitialLoad
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
    }

    private var departureScene: some View {
        GeometryReader { proxy in
            let widthScale = proxy.size.width / HomeDepartureCanvas.width
            let heightScale = proxy.size.height / HomeDepartureCanvas.interactiveContentBottom
            let sceneScale = min(widthScale, heightScale)
            let horizontalInset = max(
                0,
                (proxy.size.width - HomeDepartureCanvas.width * sceneScale) / 2
            )

            ZStack(alignment: .topLeading) {
                if sceneScale < widthScale {
                    compactHeightBackdrop(size: proxy.size)
                }

                departureCanvas
                    .frame(
                        width: HomeDepartureCanvas.width,
                        height: HomeDepartureCanvas.height,
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
    private var departureCanvas: some View {
        let width = HomeDepartureCanvas.width
        let height = HomeDepartureCanvas.height
        let layout = sceneLayout

        return ZStack(alignment: .topLeading) {
            sceneBackground(width: width, height: height)

            HomeDepartureSceneKitView(
                layout: layout,
                flag: currentRegion.map { flag($0.countryCode) },
                cityName: currentRegion?.nameZh,
                storySubtitle: storySubtitle,
                pressedEntry: pressedSceneEntry,
                reduceMotion: reduceMotion
            )
            .frame(width: width, height: height)
            .accessibilityHidden(true)
            .allowsHitTesting(false)

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

            NavigationLink(value: HomeDestination.map) {
                HomeSceneHitTarget()
            }
            .buttonStyle(HomeScenePressReportingButtonStyle(entry: .map, pressedEntry: $pressedSceneEntry))
            .frame(width: layout.map.hitSize.width, height: layout.map.hitSize.height)
            .position(
                x: width * layout.map.center.x,
                y: height * layout.map.center.y
            )
            .accessibilityLabel("世界地图")
            .accessibilityHint("查看城市并开始旅行")

            NavigationLink(value: HomeDestination.stories) {
                HomeSceneHitTarget()
            }
            .buttonStyle(HomeScenePressReportingButtonStyle(entry: .story, pressedEntry: $pressedSceneEntry))
            .frame(width: layout.story.hitSize.width, height: layout.story.hitSize.height)
            .position(
                x: width * layout.story.center.x,
                y: height * layout.story.center.y
            )
            .accessibilityLabel("剧情，\(storySubtitle)")
            .accessibilityHint("查看主线与当前城市剧情")

            NavigationLink(value: HomeDestination.activities) {
                HomeSceneHitTarget()
            }
            .buttonStyle(HomeScenePressReportingButtonStyle(entry: .activities, pressedEntry: $pressedSceneEntry))
            .frame(width: layout.activities.hitSize.width, height: layout.activities.hitSize.height)
            .position(
                x: width * layout.activities.center.x,
                y: height * layout.activities.center.y
            )
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
                    destination: .map,
                    title: "世界地图",
                    subtitle: "查看城市并开始旅行",
                    systemImage: "map"
                )
                accessibleLink(
                    destination: .stories,
                    title: "剧情",
                    subtitle: storySubtitle,
                    systemImage: "waveform.path.ecg.rectangle"
                )
                accessibleLink(
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
        destination: HomeDestination,
        title: String,
        subtitle: String,
        systemImage: String
    ) -> some View {
        NavigationLink(value: destination) {
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
}

/// SceneKit 只画视觉，透明 SwiftUI 入口继续提供原生导航、命中语义与即时按压状态。
private struct HomeSceneHitTarget: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.001))
            .contentShape(Rectangle())
    }
}

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

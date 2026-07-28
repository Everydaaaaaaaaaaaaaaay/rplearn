import DesignSystem
import DomainKit
import PersistenceKit
import SwiftUI

/// 首页聚合 Hub：城市氛围、最近会话与两个核心探索入口。
public struct HomeView: View {
    private let deps: HomeDependencies
    private let reloadToken: Int
    private let chatBuilder: @MainActor (CharacterDTO) -> AnyView
    private let onOpenMessages: @MainActor () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @State private var profile: UserProfileDTO?
    @State private var completedStories: Set<String> = []
    @State private var recentRows: [RecentChatRow] = []
    @State private var scrollOffset: CGFloat = 0

    public init(
        deps: HomeDependencies,
        reloadToken: Int = 0,
        chatBuilder: @escaping @MainActor (CharacterDTO) -> AnyView,
        onOpenMessages: @escaping @MainActor () -> Void
    ) {
        self.deps = deps
        self.reloadToken = reloadToken
        self.chatBuilder = chatBuilder
        self.onOpenMessages = onOpenMessages
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

    private var cityVistaHeight: CGFloat {
        if dynamicTypeSize.isAccessibilitySize {
            return 72
        }
        return verticalSizeClass == .compact ? 80 : 196
    }

    public var body: some View {
        ZStack {
            if let currentRegion {
                CityBackdropView(region: currentRegion, parallax: scrollOffset)
            } else {
                Color.dsBackground.ignoresSafeArea()
            }

            ScrollView {
                VStack(spacing: DSSpacing.md) {
                    cityStatusBar
                    cityVista
                    recentChats
                    exploreSection
                }
                .padding(.horizontal, DSSpacing.md)
                .padding(.top, DSSpacing.xs)
                .padding(.bottom, DSSpacing.md)
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, newValue in
                scrollOffset = newValue
            }
            .refreshable { await reload() }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: reloadToken) { await reload() }
    }

    @ViewBuilder
    private var cityVista: some View {
        if currentRegion != nil {
            Color.clear
                .frame(height: cityVistaHeight)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var cityStatusBar: some View {
        if let region = currentRegion {
            HomeStatusBar(region: region, profile: profile)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 52)
        }
    }

    private var recentChats: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack {
                Text("最近会话")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                Spacer()
                Button("查看全部 ›") { onOpenMessages() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.dsSky)
            }

            if recentRows.isEmpty {
                VStack(spacing: DSSpacing.xs) {
                    Image(systemName: "bubble.left.and.sparkles")
                        .font(.title2)
                        .foregroundStyle(Color.dsSky)
                    Text("伙伴正在等你打招呼")
                        .font(.subheadline.weight(.semibold))
                    Text("完成开场剧情后，最近的聊天会出现在这里")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DSSpacing.lg)
            } else {
                ForEach(Array(recentRows.prefix(3).enumerated()), id: \.element.id) { index, row in
                    NavigationLink {
                        chatBuilder(row.character)
                    } label: {
                        HStack(alignment: .top, spacing: DSSpacing.sm) {
                            ZStack(alignment: .topTrailing) {
                                AvatarBadge(name: row.character.card.name, size: 48)
                                if index == 0 {
                                    Circle()
                                        .fill(Color.dsDanger)
                                        .frame(width: 10, height: 10)
                                        .overlay {
                                            Circle().stroke(Color.dsSurface, lineWidth: 2)
                                        }
                                }
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(alignment: .firstTextBaseline, spacing: DSSpacing.xs) {
                                    Text(row.character.card.name)
                                        .font(.body.weight(.bold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Spacer(minLength: DSSpacing.xs)
                                    Text(row.summary.lastMessageAt, format: .relative(presentation: .named))
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                                Text(row.summary.lastMessageText.isEmpty ? "打个招呼吧 👋" : row.summary.lastMessageText)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < min(recentRows.count, 3) - 1 {
                        Divider().padding(.leading, 60)
                    }
                }
            }
        }
        .dsSurface(.elevated)
    }

    @ViewBuilder
    private var exploreSection: some View {
        if let region = currentRegion {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text("探索\(region.nameZh)")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(.primary)

                NavigationLink(value: HomeDestination.stories) {
                    ExploreCard(
                        title: "剧情",
                        subtitle: "主线 \(completedMainlineStops)/\(mainlineStopCount) · 城市 \(completedCityStories)/\(cityStoryCount)",
                        artworkName: "home_mainline_\(region.id)",
                        fallbackIcon: "book.pages.fill",
                        tint: Color.dsSky,
                        progress: totalStoryCount == 0
                            ? 0
                            : Double(completedMainlineStops + completedCityStories) / Double(totalStoryCount)
                    )
                }
                .buttonStyle(.pressableCard)

                NavigationLink(value: HomeDestination.activities) {
                    ExploreCard(
                        title: "城市活动",
                        subtitle: "参与活动，认识新朋友",
                        artworkName: "home_activity_\(region.id)",
                        fallbackIcon: "figure.walk.motion",
                        tint: Color.dsSunset,
                        progress: nil
                    )
                }
                .buttonStyle(.pressableCard)
            }
        }
    }

    private var mainlineJourney: MainlineJourney {
        MainlineCatalog.journey(starterRegionID: profile?.starterRegionID)
    }

    private var completedMainlineStops: Int {
        mainlineJourney.stops.filter {
            completedStories.contains($0.chapter.storyID)
        }.count
    }

    private var mainlineStopCount: Int {
        mainlineJourney.stops.count
    }

    private var completedCityStories: Int {
        CityStoryCatalog.chapters.filter {
            completedStories.contains($0.storyID)
        }.count
    }

    private var cityStoryCount: Int {
        CityStoryCatalog.chapters.count
    }

    private var totalStoryCount: Int {
        mainlineStopCount + cityStoryCount
    }

    private func reload() async {
        async let loadedProfile = try? deps.economyStore.profile()
        async let loadedCompleted = try? deps.storyProgress.completedStoryIDs()
        async let loadedFriends = try? deps.rosterStore.friends()
        async let loadedSummaries = try? deps.chatStore.conversationSummaries()

        profile = await loadedProfile
        completedStories = await loadedCompleted ?? []
        let friends = await loadedFriends ?? []
        let summaries = await loadedSummaries ?? []
        let friendsByID = Dictionary(uniqueKeysWithValues: friends.map { ($0.id, $0) })
        recentRows = summaries.compactMap { summary in
            friendsByID[summary.characterID].map { RecentChatRow(character: $0, summary: summary) }
        }
    }

}

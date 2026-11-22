import DesignSystem
import DomainKit
import PersistenceKit
import SwiftUI

/// 剧情二级入口：主线承载五城长篇，城市剧情提供按机票渐进开放的独立故事。
public struct StoryHubView: View {
    private let deps: HomeDependencies

    @State private var profile: UserProfileDTO?
    @State private var completed: Set<String> = []
    @State private var cityUnlockProgress = CityStoryUnlockProgress(
        profile: nil,
        availableTickets: [],
        ticketStubs: []
    )

    public init(deps: HomeDependencies) {
        self.deps = deps
        _profile = State(initialValue: deps.presentationCache?.profile)
        _completed = State(initialValue: deps.presentationCache?.completed ?? [])
        _cityUnlockProgress = State(initialValue: CityStoryUnlockProgress(
            profile: deps.presentationCache?.profile, availableTickets: deps.presentationCache?.tickets ?? [],
            ticketStubs: deps.presentationCache?.stubs ?? []))
    }

    private var journey: MainlineJourney {
        MainlineCatalog.journey(starterRegionID: profile?.starterRegionID)
    }

    private var completedMainlineCount: Int {
        journey.stops.filter { completed.contains($0.chapter.storyID) }.count
    }

    private var completedCityCount: Int {
        CityStoryCatalog.chapters.filter { completed.contains($0.storyID) }.count
    }

    private var unlockedCityCount: Int {
        cityUnlockProgress.unlockedChapterCount
    }

    /// 主线下一站；全部读完时回到旅程起点。
    private var nextMainlineRegionID: String? {
        (journey.stops.first { !completed.contains($0.chapter.storyID) } ?? journey.stops.first)?.regionID
    }

    /// 第一篇已开放且未读的城市故事。
    private var nextCityRegionID: String? {
        let open = CityStoryCatalog.chapters.prefix(max(unlockedCityCount, 1))
        return (open.first { !completed.contains($0.storyID) } ?? CityStoryCatalog.chapters.first)?.regionID
    }

    @State private var hasEntered = false

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Puff.Space.m) {
                NavigationLink(value: HomeDestination.mainline) {
                    categoryCard(
                        eyebrow: "五城长篇",
                        title: "主线剧情",
                        icon: "map.fill",
                        candy: .sky,
                        regionID: nextMainlineRegionID,
                        viewport: .west,
                        completed: completedMainlineCount,
                        total: journey.stops.count,
                        unit: "章",
                        badge: "全部开放"
                    )
                }
                .buttonStyle(PuffCardButtonStyle(radius: Puff.Radius.huge))
                .puffZoomSource(id: HomeDestination.mainline, cornerRadius: Puff.Radius.huge)
                .accessibilityIdentifier("story.mainline")
                .puffEntrance(index: 0, isShown: hasEntered)

                NavigationLink(value: HomeDestination.cityStories) {
                    categoryCard(
                        eyebrow: "十五城短篇",
                        title: "城市剧情",
                        icon: "building.2.fill",
                        candy: .tangerine,
                        regionID: nextCityRegionID,
                        viewport: .east,
                        completed: completedCityCount,
                        total: CityStoryCatalog.chapters.count,
                        unit: "篇",
                        badge: "已开放 \(unlockedCityCount) 篇"
                    )
                }
                .buttonStyle(PuffCardButtonStyle(radius: Puff.Radius.huge))
                .puffZoomSource(id: HomeDestination.cityStories, cornerRadius: Puff.Radius.huge)
                .accessibilityIdentifier("story.cities")
                .puffEntrance(index: 1, isShown: hasEntered)
            }
            .padding(.horizontal, Puff.Space.m)
            .padding(.top, Puff.Space.xs)
            .padding(.bottom, Puff.Space.xl)
        }
        .background { PuffPageBackdrop() }
        .puffPageTint(.mint)
        .navigationTitle("剧情")
        .task {
            if !hasEntered {
                try? await Task.sleep(for: .milliseconds(40))
                hasEntered = true
            }
            await reload()
        }
    }

    private func categoryCard(
        eyebrow: String,
        title: String,
        icon: String,
        candy: PuffCandy,
        regionID: String?,
        viewport: PuffCityScene.Viewport,
        completed: Int,
        total: Int,
        unit: String,
        badge: String
    ) -> some View {
        VStack(alignment: .leading, spacing: Puff.Space.s) {
            PuffCityScene(regionID: regionID, viewport: viewport)
                .frame(height: 136)
                .clipShape(RoundedRectangle(cornerRadius: Puff.Radius.huge - 6, style: .continuous))
                .padding([.horizontal, .top], 6)

            HStack(spacing: Puff.Space.s) {
                PuffIconBubble(icon, candy: candy, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.puff(.title3, Puff.Weight.title))
                        .foregroundStyle(Puff.Palette.ink)
                    Text(eyebrow)
                        .font(.puff(.caption, Puff.Weight.label))
                        .foregroundStyle(Puff.Palette.inkSoft)
                }
                Spacer(minLength: Puff.Space.xs)
                PuffTag(badge, candy: candy)
            }
            .padding(.horizontal, Puff.Space.m)

            HStack(spacing: Puff.Space.s) {
                progressMeter(completed: completed, total: total, candy: candy)
                Text("\(completed) / \(total) \(unit)")
                    .font(.puff(.subheadline, Puff.Weight.emphasis))
                    .monospacedDigit()
                    .foregroundStyle(candy.deep)
                    .fixedSize()
            }
            .padding(.horizontal, Puff.Space.m)
            .padding(.bottom, Puff.Space.m)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// 章节少时用一排圆点，多时用进度条。
    @ViewBuilder
    private func progressMeter(completed: Int, total: Int, candy: PuffCandy) -> some View {
        if total <= 8 {
            HStack(spacing: 6) {
                ForEach(0..<total, id: \.self) { index in
                    Circle()
                        .fill(index < completed ? candy.base : Puff.Palette.cloud)
                        .overlay { Circle().strokeBorder(index < completed ? candy.lip : Puff.Palette.line, lineWidth: 1.5) }
                        .frame(width: 16, height: 16)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true)
        } else {
            GeometryReader { proxy in
                Capsule()
                    .fill(Puff.Palette.cloud)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(candy.base)
                            .frame(width: max(proxy.size.width * CGFloat(completed) / CGFloat(max(total, 1)), completed > 0 ? 12 : 0))
                    }
            }
            .frame(height: 12)
            .accessibilityHidden(true)
        }
    }

    private func reload() async {
        if let cache = deps.presentationCache {
            await cache.refreshLocal(economy: deps.economyStore, items: deps.itemStore,
                progress: deps.storyProgress, ticketStubs: deps.ticketStubStore)
            guard !Task.isCancelled else { return }
            profile = cache.profile
            completed = cache.completed
            cityUnlockProgress = CityStoryUnlockProgress(profile: cache.profile, availableTickets: cache.tickets, ticketStubs: cache.stubs)
            return
        }
        async let loadedProfile = try? deps.economyStore.profile()
        async let loadedCompleted = try? deps.storyProgress.completedStoryIDs()
        async let loadedTickets = try? deps.itemStore.unconsumedTickets()
        async let loadedStubs = try? deps.ticketStubStore.all()
        let resolvedProfile = await loadedProfile
        profile = resolvedProfile
        completed = DepartureStoryIdentity.catalogCompletionIDs(await loadedCompleted ?? [])
        cityUnlockProgress = CityStoryUnlockProgress(
            profile: resolvedProfile,
            availableTickets: await loadedTickets ?? [],
            ticketStubs: await loadedStubs ?? []
        )
    }
}

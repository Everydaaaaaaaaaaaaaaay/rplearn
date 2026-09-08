import DesignSystem
import DomainKit
import PersistenceKit
import SwiftUI

public struct CityStoryListView: View {
    private let deps: HomeDependencies
    private let onOpenChapter: @MainActor (CityStoryChapter) -> Void

    @State private var profile: UserProfileDTO?
    @State private var completed: Set<String> = []
    @State private var unlockProgress = CityStoryUnlockProgress(
        profile: nil,
        availableTickets: [],
        ticketStubs: []
    )

    public init(
        deps: HomeDependencies,
        onOpenChapter: @escaping @MainActor (CityStoryChapter) -> Void
    ) {
        self.deps = deps
        self.onOpenChapter = onOpenChapter
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DSSpacing.sm) {
                header
                ForEach(Array(CityStoryCatalog.chapters.enumerated()), id: \.element.id) { index, chapter in
                    if index < unlockProgress.unlockedChapterCount {
                        Button {
                            open(chapter)
                        } label: {
                            chapterCard(chapter, index: index)
                        }
                        .buttonStyle(.pressableCard)
                        .accessibilityHint("在当前位置直接打开章节")
                    } else {
                        chapterCard(chapter, index: index)
                    }
                }
            }
            .padding(DSSpacing.md)
        }
        .background(Color.dsBackground)
        .navigationTitle("城市剧情")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .onAppear { Task { await reload() } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack {
                Text("十五城故事集")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                Spacer()
                Text("\(completed.filter(isCityStoryID).count) / \(CityStoryCatalog.chapters.count) 篇")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text("前六篇默认开放；每累计一张机票再开放三篇。机票使用后不会回锁，已开放剧情可在当前位置直接开始。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, DSSpacing.xs)
    }

    private func chapterCard(_ chapter: CityStoryChapter, index: Int) -> some View {
        let region = deps.regionCatalog.region(id: chapter.regionID)
        let isUnlocked = index < unlockProgress.unlockedChapterCount
        let isCompleted = completed.contains(chapter.storyID)
        let accent = DSScenePalette.city(chapter.regionID).accent
        let canOpenForIdentity = profile.map {
            deps.access.allowsStory(chapter.storyID, starterRegionID: $0.starterRegionID)
        } ?? false
        let requiredTickets = CityStoryCatalog.requiredTicketCount(forChapterAt: index)
        let remainingTickets = max(0, requiredTickets - unlockProgress.earnedTicketCount)

        return StoryChapterCard(
            artworkName: DSCitySceneAssets.imageName(for: .contacts, regionID: chapter.regionID),
            countryCode: region?.countryCode,
            artworkBadge: nil,
            eyebrow: region?.nameZh ?? chapter.regionID,
            badge: nil,
            title: chapter.title,
            subtitle: chapter.subtitle,
            statusText: isUnlocked
                ? (canOpenForIdentity ? (isCompleted ? "可重温" : "开展剧情") : "登录后开展")
                : "再获得 \(remainingTickets) 张机票解锁",
            statusIcon: isUnlocked
                ? (canOpenForIdentity
                    ? (isCompleted ? "checkmark.circle.fill" : "play.circle.fill")
                    : "person.crop.circle.badge.plus")
                : "ticket.fill",
            accent: accent,
            isHighlighted: false,
            isDimmed: !isUnlocked,
            isLoading: false
        )
    }

    private func isCityStoryID(_ storyID: String) -> Bool {
        CityStoryCatalog.chapters.contains { $0.storyID == storyID }
    }

    private func reload() async {
        async let loadedProfile = try? deps.economyStore.profile()
        async let loadedCompleted = try? deps.storyProgress.completedStoryIDs()
        async let loadedTickets = try? deps.itemStore.unconsumedTickets()
        async let loadedStubs = try? deps.ticketStubStore.all()
        let resolvedProfile = await loadedProfile
        profile = resolvedProfile
        completed = await loadedCompleted ?? []
        unlockProgress = CityStoryUnlockProgress(
            profile: resolvedProfile,
            availableTickets: await loadedTickets ?? [],
            ticketStubs: await loadedStubs ?? []
        )
    }

    private func open(_ chapter: CityStoryChapter) {
        guard let profile else { return }
        guard deps.access.allowsStory(chapter.storyID, starterRegionID: profile.starterRegionID) else {
            deps.access.requestSignIn("游客可以体验起始城市的剧情首站，登录后即可继续后续旅程。")
            return
        }
        Haptics.impact(.light)
        onOpenChapter(chapter)
    }
}

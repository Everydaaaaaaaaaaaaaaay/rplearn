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
        Group {
            if profile != nil {
                StoryCoverFlow(
                    items: coverItems,
                    preferredItemID: preferredItemID,
                    accessibilityIdentifier: "story.coverFlow.city"
                ) { storyID in
                    guard let chapter = CityStoryCatalog.chapters.first(where: { $0.storyID == storyID }) else {
                        return
                    }
                    open(chapter)
                }
            } else {
                ZStack {
                    StoryTheaterBackdrop(
                        accent: .dsFoilGold,
                        spotlightVisible: true,
                        reduceTransparency: false
                    )
                    ProgressView()
                        .tint(.white)
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("城市剧情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .tint(.white)
        .task { await reload() }
        .onAppear { Task { await reload() } }
    }

    private var coverItems: [StoryCoverItem] {
        CityStoryCatalog.chapters.enumerated().map { index, chapter in
            coverItem(chapter, index: index)
        }
    }

    private var preferredItemID: String? {
        coverItems.first(where: { $0.isEnabled && !$0.isCompleted })?.id
            ?? coverItems.first(where: \.isEnabled)?.id
            ?? coverItems.first?.id
    }

    private func coverItem(_ chapter: CityStoryChapter, index: Int) -> StoryCoverItem {
        let region = deps.regionCatalog.region(id: chapter.regionID)
        let isUnlocked = index < unlockProgress.unlockedChapterCount
        let isCompleted = completed.contains(chapter.storyID)
        let accent = DSScenePalette.city(chapter.regionID).accent
        let canOpenForIdentity = profile.map {
            deps.access.allowsStory(chapter.storyID, starterRegionID: $0.starterRegionID)
        } ?? false
        let requiredTickets = CityStoryCatalog.requiredTicketCount(forChapterAt: index)
        let remainingTickets = max(0, requiredTickets - unlockProgress.earnedTicketCount)

        return StoryCoverItem(
            id: chapter.storyID,
            artworkName: DSCitySceneAssets.imageName(for: .contacts, regionID: chapter.regionID),
            sequenceText: "短篇 \(padded(index + 1))",
            eyebrow: region?.nameZh ?? chapter.regionID,
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
            isEnabled: isUnlocked && canOpenForIdentity,
            isCompleted: isCompleted,
            isDimmed: !isUnlocked
        )
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

    private func padded(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}

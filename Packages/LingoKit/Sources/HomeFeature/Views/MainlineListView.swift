import DesignSystem
import DomainKit
import PersistenceKit
import SwiftUI

public struct MainlineListView: View {
    private let deps: HomeDependencies
    private let onOpenChapter: @MainActor (MainlineChapter) -> Void

    @State private var profile: UserProfileDTO?
    @State private var completed: Set<String> = []

    public init(
        deps: HomeDependencies,
        onOpenChapter: @escaping @MainActor (MainlineChapter) -> Void
    ) {
        self.deps = deps
        self.onOpenChapter = onOpenChapter
    }

    private var journey: MainlineJourney? {
        profile.map { MainlineCatalog.journey(starterRegionID: $0.starterRegionID) }
    }

    public var body: some View {
        Group {
            if let journey, let profile {
                StoryCoverFlow(
                    items: coverItems(journey: journey, profile: profile),
                    preferredItemID: preferredItemID(journey: journey),
                    accessibilityIdentifier: "story.coverFlow.mainline"
                ) { storyID in
                    guard let stop = journey.stops.first(where: { $0.chapter.storyID == storyID }) else {
                        return
                    }
                    open(stop, profile: profile)
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
        .navigationTitle("主线剧情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .tint(.white)
        .task { await reload() }
        .onAppear { Task { await reload() } }
    }

    private func coverItems(journey: MainlineJourney, profile: UserProfileDTO) -> [StoryCoverItem] {
        journey.stops.enumerated().map { index, stop in
            coverItem(stop, index: index, status: stopStatus(index: index, journey: journey), profile: profile)
        }
    }

    private func preferredItemID(journey: MainlineJourney) -> String? {
        journey.stops.first(where: { !completed.contains($0.chapter.storyID) })?.chapter.storyID
            ?? journey.stops.first?.chapter.storyID
    }

    private enum StopStatus: Equatable {
        case completed
        case next
        case available
    }

    private func stopStatus(index: Int, journey: MainlineJourney) -> StopStatus {
        let stop = journey.stops[index]
        if completed.contains(stop.chapter.storyID) {
            return .completed
        }
        let activeIndex = journey.stops.firstIndex {
            !completed.contains($0.chapter.storyID)
        } ?? journey.stops.count
        return index == activeIndex ? .next : .available
    }

    private func coverItem(
        _ stop: MainlineStop,
        index: Int,
        status: StopStatus,
        profile: UserProfileDTO
    ) -> StoryCoverItem {
        let chapter = stop.chapter
        let isCompleted = status == .completed
        let region = deps.regionCatalog.region(id: stop.regionID)
        let accent = DSScenePalette.city(chapter.regionID).accent
        let canOpenForIdentity = deps.access.allowsStory(
            chapter.storyID,
            starterRegionID: profile.starterRegionID
        )

        return StoryCoverItem(
            id: chapter.storyID,
            artworkName: DSCitySceneAssets.imageName(for: .messages, regionID: chapter.regionID),
            sequenceText: stop.isFinale ? "终章" : "第 \(padded(index + 1)) 站",
            eyebrow: region?.nameZh ?? stop.regionID,
            title: stop.displayTitle,
            subtitle: chapter.subtitle,
            statusText: canOpenForIdentity
                ? (isCompleted ? "可重温" : "开展剧情")
                : "登录后开展",
            statusIcon: canOpenForIdentity
                ? (isCompleted ? "checkmark.circle.fill" : "play.circle.fill")
                : "person.crop.circle.badge.plus",
            accent: accent,
            isEnabled: canOpenForIdentity,
            isCompleted: isCompleted,
            isDimmed: false
        )
    }

    private func open(_ stop: MainlineStop, profile: UserProfileDTO) {
        guard deps.access.allowsStory(stop.chapter.storyID, starterRegionID: profile.starterRegionID) else {
            deps.access.requestSignIn("游客可以体验起始城市的剧情首站，登录后即可继续后续旅程。")
            return
        }
        Haptics.impact(.light)
        onOpenChapter(stop.chapter)
    }

    private func reload() async {
        profile = try? await deps.economyStore.profile()
        completed = (try? await deps.storyProgress.completedStoryIDs()) ?? []
    }

    private func padded(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}

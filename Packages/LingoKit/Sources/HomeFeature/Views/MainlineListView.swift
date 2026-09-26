import BackendKit
import DesignSystem
import DomainKit
import PersistenceKit
import SwiftUI

public struct MainlineListView: View {
    private let deps: HomeDependencies
    private let onOpenChapter: @MainActor (MainlineChapter) -> Void

    @State private var progress: BackendMainlineProgress?
    @State private var progressError: String?
    @State private var profile: UserProfileDTO?

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
        .overlay(alignment: .bottom) {
            if let progressError {
                Button { Task { await reload() } } label: { Label(progressError, systemImage: "arrow.clockwise").font(.footnote).padding().background(.regularMaterial, in: Capsule()) }
                    .padding().accessibilityLabel("旅程进度更新失败，点击重试")
            }
        }
        .task { await reload() }
    }

    private func coverItems(journey: MainlineJourney, profile: UserProfileDTO) -> [StoryCoverItem] {
        journey.stops.enumerated().map { index, stop in
            coverItem(stop, index: index, profile: profile)
        }
    }

    private func preferredItemID(journey: MainlineJourney) -> String? {
        let nextRegion = progress?.chapters.first(where: { $0.state != "completed" })?.regionId
        return journey.stops.first(where: { $0.regionID == nextRegion })?.chapter.storyID
            ?? journey.stops.first?.chapter.storyID
    }

    private func coverItem(
        _ stop: MainlineStop,
        index: Int,
        profile: UserProfileDTO
    ) -> StoryCoverItem {
        let chapter = stop.chapter
        let gate = progress?.chapters.first { $0.regionId == stop.regionID }
        let isCompleted = gate?.state == "completed"
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
            statusText: canOpenForIdentity ? (gate?.statusText ?? "联网确认旅程进度") : "登录后开展",
            statusIcon: isCompleted ? "checkmark.circle.fill" : gate?.canOpen == true ? "play.circle.fill" : "lock.fill",
            accent: accent,
            isEnabled: canOpenForIdentity && gate?.canOpen == true,
            isCompleted: isCompleted,
            isDimmed: false
        )
    }

    private func open(_ stop: MainlineStop, profile: UserProfileDTO) {
        guard deps.access.allowsStory(stop.chapter.storyID, starterRegionID: profile.starterRegionID) else {
            deps.access.requestSignIn("游客可以体验起始城市的剧情首站，登录后即可继续后续旅程。")
            return
        }
        guard progress?.chapters.first(where: { $0.regionId == stop.regionID })?.canOpen == true else { return }
        Haptics.impact(.light)
        onOpenChapter(stop.chapter)
    }

    private func reload() async {
        profile = try? await deps.economyStore.profile()
        do {
            guard let mainline = deps.mainline else { progressError = "旅程进度暂不可用，点击重试"; return }
            progress = try await mainline.mainlineProgress(); progressError = nil
        } catch { progress = nil; progressError = "旅程进度更新失败，点击重试" }
    }

    private func padded(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}

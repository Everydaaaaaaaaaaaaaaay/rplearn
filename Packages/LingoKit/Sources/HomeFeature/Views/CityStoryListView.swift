import DesignSystem
import DomainKit
import PersistenceKit
import SwiftUI

public struct CityStoryListView: View {
    private let deps: HomeDependencies
    private let onOpenChapter: @MainActor (CityStoryChapter) -> Void

    @State private var profile: UserProfileDTO?
    @State private var completed: Set<String> = []
    @State private var travelingStoryID: String?
    @State private var pendingChapter: CityStoryChapter?
    @State private var flight: StoryTravelPresentation?
    @State private var travelError: String?

    public init(
        deps: HomeDependencies,
        onOpenChapter: @escaping @MainActor (CityStoryChapter) -> Void
    ) {
        self.deps = deps
        self.onOpenChapter = onOpenChapter
    }

    private var orderedChapters: [CityStoryChapter] {
        guard let profile else { return CityStoryCatalog.chapters }
        let unlocked = Set(profile.unlockedRegionIDs + [profile.currentRegionID])
        return CityStoryCatalog.chapters.sorted { lhs, rhs in
            sortRank(lhs, profile: profile, unlocked: unlocked)
                < sortRank(rhs, profile: profile, unlocked: unlocked)
        }
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DSSpacing.sm) {
                header
                ForEach(orderedChapters) { chapter in
                    let access = access(to: chapter)
                    if access.canOpen {
                        Button {
                            open(chapter, access: access)
                        } label: {
                            chapterCard(chapter)
                        }
                        .buttonStyle(.pressableCard)
                        .disabled(travelingStoryID != nil)
                        .accessibilityHint(
                            access == .unlockedAway
                                ? "自动飞往剧情所在城市后打开章节"
                                : "打开章节"
                        )
                    } else {
                        chapterCard(chapter)
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
        .fullScreenCover(item: $flight, onDismiss: finishTravel) { presentation in
            StoryTravelTransitionView(presentation: presentation) {
                flight = nil
            }
        }
        .dsModalDialog(
            isPresented: Binding(
                get: { travelError != nil },
                set: { if !$0 { travelError = nil } }
            ),
            configuration: travelErrorDialog,
            onPrimary: {}
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack {
                Text("十三城故事集")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                Spacer()
                Text("\(completed.filter(isCityStoryID).count) / \(CityStoryCatalog.chapters.count) 篇")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(deps.access.isGuest ? "游客可体验起始城市的城市剧情；登录后可以探索更多城市。" : "城市剧情会在首次抵达后解锁。已解锁剧情可从任意城市搭乘剧情专机直接开展。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, DSSpacing.xs)
    }

    private func chapterCard(_ chapter: CityStoryChapter) -> some View {
        let region = deps.regionCatalog.region(id: chapter.regionID)
        let access = access(to: chapter)
        let isHere = access == .current
        let isUnlocked = access.canOpen
        let isCompleted = completed.contains(chapter.storyID)
        let accent = DSScenePalette.city(chapter.regionID).accent
        let isLoading = travelingStoryID == chapter.storyID

        return StoryChapterCard(
            artworkName: "home_mainline_\(chapter.regionID)",
            countryCode: region?.countryCode,
            artworkBadge: nil,
            eyebrow: region?.nameZh ?? chapter.regionID,
            badge: isHere ? "当前城市" : nil,
            title: chapter.title,
            subtitle: chapter.subtitle,
            statusText: isLoading
                ? "正在同步位置…"
                : actionText(
                    access: access,
                    isCompleted: isCompleted,
                    regionName: region?.nameZh
                ),
            statusIcon: statusIcon(access: access, isCompleted: isCompleted),
            accent: accent,
            isHighlighted: isHere,
            isDimmed: !isUnlocked,
            isLoading: isLoading
        )
    }

    private func sortRank(
        _ chapter: CityStoryChapter,
        profile: UserProfileDTO,
        unlocked: Set<String>
    ) -> Int {
        if chapter.regionID == profile.currentRegionID { return 0 }
        if unlocked.contains(chapter.regionID) { return 1 }
        return 2
    }

    private func access(to chapter: CityStoryChapter) -> StoryRegionAccess {
        guard let profile else { return .locked }
        return StoryRegionAccess(regionID: chapter.regionID, profile: profile)
    }

    private func actionText(
        access: StoryRegionAccess,
        isCompleted: Bool,
        regionName: String?
    ) -> String {
        switch access {
        case .current:
            return isCompleted ? "可重温" : "开展剧情"
        case .unlockedAway:
            return isCompleted
                ? "飞往\(regionName ?? "剧情城市")重温"
                : "飞往\(regionName ?? "剧情城市")开展剧情"
        case .locked:
            return "首次抵达后解锁"
        }
    }

    private func statusIcon(access: StoryRegionAccess, isCompleted: Bool) -> String {
        switch access {
        case .current:
            isCompleted ? "checkmark.circle.fill" : "play.circle.fill"
        case .unlockedAway:
            "airplane"
        case .locked:
            "lock.fill"
        }
    }

    private func isCityStoryID(_ storyID: String) -> Bool {
        CityStoryCatalog.chapters.contains { $0.storyID == storyID }
    }

    private func reload() async {
        async let loadedProfile = try? deps.economyStore.profile()
        async let loadedCompleted = try? deps.storyProgress.completedStoryIDs()
        profile = await loadedProfile
        completed = await loadedCompleted ?? []
    }

    private func open(_ chapter: CityStoryChapter, access: StoryRegionAccess) {
        guard let profile else { return }
        guard deps.access.allowsStory(chapter.storyID, starterRegionID: profile.starterRegionID) else {
            deps.access.requestSignIn("游客可以体验起始城市的剧情首站，登录后即可继续后续旅程。")
            return
        }
        switch access {
        case .current:
            Haptics.impact(.light)
            onOpenChapter(chapter)
        case .unlockedAway:
            beginTravel(to: chapter)
        case .locked:
            break
        }
    }

    private func beginTravel(to chapter: CityStoryChapter) {
        guard travelingStoryID == nil,
              let profile,
              let destination = deps.regionCatalog.region(id: chapter.regionID)
        else { return }

        let originName = deps.regionCatalog.region(id: profile.currentRegionID)?.nameZh ?? "当前城市"
        travelingStoryID = chapter.storyID
        Haptics.impact(.light)

        Task {
            do {
                _ = try await deps.travelService.travel(to: destination)
                guard !Task.isCancelled else { return }
                pendingChapter = chapter
                flight = StoryTravelPresentation(
                    fromName: originName,
                    toName: destination.nameZh,
                    storyTitle: chapter.title
                )
            } catch TravelService.TravelError.alreadyThere {
                travelingStoryID = nil
                await reload()
                onOpenChapter(chapter)
            } catch {
                travelingStoryID = nil
                travelError = storyTravelErrorMessage(error)
            }
        }
    }

    private func finishTravel() {
        guard let chapter = pendingChapter else {
            travelingStoryID = nil
            return
        }
        pendingChapter = nil
        travelingStoryID = nil
        Task {
            await reload()
            onOpenChapter(chapter)
        }
    }

    private var travelErrorDialog: DSModalDialogConfiguration {
        DSModalDialogConfiguration(
            eyebrow: "航程未开始",
            title: "暂时无法前往剧情城市",
            message: travelError ?? "位置同步暂时没有完成，请稍后重试。",
            icon: "airplane.circle.fill",
            tone: .warning,
            primaryTitle: "知道了",
            primaryIcon: "checkmark",
            primaryRole: .cancel,
            secondaryTitle: nil
        )
    }

}

import DesignSystem
import DomainKit
import PersistenceKit
import SwiftUI

public struct MainlineListView: View {
    private let deps: HomeDependencies
    private let onOpenChapter: @MainActor (MainlineChapter) -> Void

    @State private var profile: UserProfileDTO?
    @State private var completed: Set<String> = []
    @State private var travelingStoryID: String?
    @State private var pendingChapter: MainlineChapter?
    @State private var flight: StoryTravelPresentation?
    @State private var travelError: String?

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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DSSpacing.sm) {
                if let journey, let profile {
                    header(journey)
                    ForEach(Array(journey.stops.enumerated()), id: \.element.id) { index, stop in
                        let status = stopStatus(index: index, journey: journey)
                        let access = StoryRegionAccess(
                            regionID: stop.regionID,
                            profile: profile
                        )
                        if access.canOpen {
                            Button {
                                open(stop, access: access)
                            } label: {
                                stopCard(stop, index: index, status: status, profile: profile)
                            }
                            .buttonStyle(.pressableCard)
                            .disabled(travelingStoryID != nil)
                            .accessibilityHint(
                                access == .unlockedAway
                                    ? "自动飞往剧情所在城市后打开章节"
                                    : "打开章节"
                            )
                        } else {
                            stopCard(stop, index: index, status: status, profile: profile)
                        }
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 220)
                }
            }
            .padding(DSSpacing.md)
        }
        .background(Color.dsBackground)
        .navigationTitle("主线剧情")
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

    private func header(_ journey: MainlineJourney) -> some View {
        let done = journey.stops.filter { completed.contains($0.chapter.storyID) }.count
        return VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("五城回声")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.dsSky)
                    Text(journey.title)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                }
                Spacer()
                Text("\(done) / \(journey.stops.count) 站")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text("五站剧情已全部开放，可自由选择章节；每站进度独立保存。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ProgressView(value: Double(done) / Double(journey.stops.count))
                .tint(.dsSuccess)
        }
        .padding(.bottom, DSSpacing.xs)
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

    private func stopCard(
        _ stop: MainlineStop,
        index: Int,
        status: StopStatus,
        profile: UserProfileDTO
    ) -> some View {
        let chapter = stop.chapter
        let isCompleted = status == .completed
        let isNext = status == .next
        let access = StoryRegionAccess(regionID: stop.regionID, profile: profile)
        let isHere = access == .current
        let region = deps.regionCatalog.region(id: stop.regionID)
        let accent = DSScenePalette.city(chapter.regionID).accent
        let isLoading = travelingStoryID == chapter.storyID

        return StoryChapterCard(
            artworkName: "home_mainline_\(chapter.regionID)",
            countryCode: region?.countryCode,
            artworkBadge: index + 1 < 10 ? "0\(index + 1)" : "\(index + 1)",
            eyebrow: "第 \(index + 1) 站 · \(region?.nameZh ?? stop.regionID)",
            badge: isHere ? "当前城市" : nil,
            title: stop.displayTitle,
            subtitle: chapter.subtitle,
            statusText: isLoading
                ? "正在同步位置…"
                : actionText(status: status, access: access, regionName: region?.nameZh),
            statusIcon: statusIcon(status: status, access: access),
            accent: accent,
            isHighlighted: isNext || (isCompleted && isHere),
            isDimmed: false,
            isLoading: isLoading
        )
    }

    private func actionText(
        status: StopStatus,
        access: StoryRegionAccess,
        regionName: String?
    ) -> String {
        switch status {
        case .completed:
            switch access {
            case .current:
                "可重温"
            case .unlockedAway:
                "飞往\(regionName ?? "剧情城市")重温"
            case .locked:
                "请先在地图解锁\(regionName ?? "剧情城市")"
            }
        case .next, .available:
            switch access {
            case .current:
                "开展剧情"
            case .unlockedAway:
                "飞往\(regionName ?? "剧情城市")开展剧情"
            case .locked:
                "请先在地图解锁\(regionName ?? "目标城市")"
            }
        }
    }

    private func statusIcon(status: StopStatus, access: StoryRegionAccess) -> String {
        switch status {
        case .completed:
            access == .unlockedAway ? "airplane" : "checkmark.circle.fill"
        case .next, .available:
            switch access {
            case .current:
                "play.circle.fill"
            case .unlockedAway:
                "airplane"
            case .locked:
                "ticket.fill"
            }
        }
    }

    private func open(_ stop: MainlineStop, access: StoryRegionAccess) {
        switch access {
        case .current:
            Haptics.impact(.light)
            onOpenChapter(stop.chapter)
        case .unlockedAway:
            beginTravel(to: stop)
        case .locked:
            break
        }
    }

    private func beginTravel(to stop: MainlineStop) {
        let chapter = stop.chapter
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
                    storyTitle: stop.displayTitle
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

    private func reload() async {
        profile = try? await deps.economyStore.profile()
        completed = (try? await deps.storyProgress.completedStoryIDs()) ?? []
    }
}

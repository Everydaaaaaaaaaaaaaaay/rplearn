import DesignSystem
import DomainKit
import PersistenceKit
import SwiftUI

public struct MainlineListView: View {
    private let deps: HomeDependencies
    @State private var profile: UserProfileDTO?
    @State private var completed: Set<String> = []

    public init(deps: HomeDependencies) {
        self.deps = deps
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
                        if canOpen(stop, status: status, profile: profile) {
                            NavigationLink(value: stop.chapter) {
                                stopCard(stop, index: index, status: status, profile: profile)
                            }
                            .buttonStyle(.pressableCard)
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
        .task { await reload() }
        .onAppear { Task { await reload() } }
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
            Text("依次前往五座城市推进故事。完成当前章节后，下一站才会开放。")
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
        case active
        case future
    }

    private func stopStatus(index: Int, journey: MainlineJourney) -> StopStatus {
        let stop = journey.stops[index]
        if completed.contains(stop.chapter.storyID) {
            return .completed
        }
        let activeIndex = journey.stops.firstIndex {
            !completed.contains($0.chapter.storyID)
        } ?? journey.stops.count
        return index == activeIndex ? .active : .future
    }

    private func canOpen(
        _ stop: MainlineStop,
        status: StopStatus,
        profile: UserProfileDTO
    ) -> Bool {
        status != .future && profile.currentRegionID == stop.regionID
    }

    private func stopCard(
        _ stop: MainlineStop,
        index: Int,
        status: StopStatus,
        profile: UserProfileDTO
    ) -> some View {
        let chapter = stop.chapter
        let isCompleted = status == .completed
        let isActive = status == .active
        let isFuture = status == .future
        let isHere = profile.currentRegionID == stop.regionID
        let region = deps.regionCatalog.region(id: stop.regionID)
        let accent = DSScenePalette.city(chapter.regionID).accent

        return StoryChapterCard(
            artworkName: "home_mainline_\(chapter.regionID)",
            countryCode: region?.countryCode,
            artworkBadge: index + 1 < 10 ? "0\(index + 1)" : "\(index + 1)",
            eyebrow: "第 \(index + 1) 站 · \(region?.nameZh ?? stop.regionID)",
            badge: isHere ? "当前城市" : nil,
            title: chapter.title,
            subtitle: chapter.subtitle,
            statusText: actionText(status: status, isHere: isHere, regionName: region?.nameZh),
            statusIcon: statusIcon(status: status, isHere: isHere),
            accent: accent,
            isHighlighted: isActive || (isCompleted && isHere),
            isDimmed: isFuture
        )
    }

    private func actionText(status: StopStatus, isHere: Bool, regionName: String?) -> String {
        switch status {
        case .completed:
            isHere ? "可重温" : "回到\(regionName ?? "这座城市")后重温"
        case .active:
            isHere ? "开展剧情" : "请先前往\(regionName ?? "目标城市")"
        case .future:
            "完成上一站后解锁"
        }
    }

    private func statusIcon(status: StopStatus, isHere: Bool) -> String {
        switch status {
        case .completed:
            "checkmark.circle.fill"
        case .active:
            isHere ? "play.circle.fill" : "location.fill"
        case .future:
            "lock.fill"
        }
    }

    private func reload() async {
        profile = try? await deps.economyStore.profile()
        completed = (try? await deps.storyProgress.completedStoryIDs()) ?? []
    }
}

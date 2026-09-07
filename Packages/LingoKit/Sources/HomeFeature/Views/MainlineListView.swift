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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DSSpacing.sm) {
                if let journey, let profile {
                    header(journey)
                    ForEach(Array(journey.stops.enumerated()), id: \.element.id) { index, stop in
                        let status = stopStatus(index: index, journey: journey)
                        Button {
                            open(stop, profile: profile)
                        } label: {
                            stopCard(stop, index: index, status: status, profile: profile)
                        }
                        .buttonStyle(.pressableCard)
                        .accessibilityIdentifier("story.chapter.\(stop.chapter.storyID)")
                        .accessibilityHint("在当前位置直接打开章节")
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
    }

    private func header(_ journey: MainlineJourney) -> some View {
        let done = journey.stops.filter { completed.contains($0.chapter.storyID) }.count
        return VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("出发之后")
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
            Text(deps.access.isGuest ? "章节不再要求飞往当地。游客可体验第一站；登录后即可在当前位置继续完整主线。" : "五章均可在当前位置直接开始，不再切换所在城市；每章进度独立保存。")
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
        let region = deps.regionCatalog.region(id: stop.regionID)
        let accent = DSScenePalette.city(chapter.regionID).accent
        let canOpenForIdentity = deps.access.allowsStory(
            chapter.storyID,
            starterRegionID: profile.starterRegionID
        )

        return StoryChapterCard(
            artworkName: DSCitySceneAssets.imageName(for: .messages, regionID: chapter.regionID),
            countryCode: region?.countryCode,
            artworkBadge: index + 1 < 10 ? "0\(index + 1)" : "\(index + 1)",
            eyebrow: "第 \(index + 1) 站 · \(region?.nameZh ?? stop.regionID)",
            badge: nil,
            title: stop.displayTitle,
            subtitle: chapter.subtitle,
            statusText: canOpenForIdentity
                ? (isCompleted ? "可重温" : "开展剧情")
                : "登录后开展",
            statusIcon: canOpenForIdentity
                ? (isCompleted ? "checkmark.circle.fill" : "play.circle.fill")
                : "person.crop.circle.badge.plus",
            accent: accent,
            isHighlighted: isNext,
            isDimmed: false,
            isLoading: false
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
}

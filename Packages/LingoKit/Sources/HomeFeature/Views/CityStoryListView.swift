import DesignSystem
import DomainKit
import PersistenceKit
import SwiftUI

public struct CityStoryListView: View {
    private let deps: HomeDependencies

    @State private var profile: UserProfileDTO?
    @State private var completed: Set<String> = []

    public init(deps: HomeDependencies) {
        self.deps = deps
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
                    if canOpen(chapter) {
                        NavigationLink(value: chapter) {
                            chapterCard(chapter)
                        }
                        .buttonStyle(.pressableCard)
                    } else {
                        chapterCard(chapter)
                    }
                }
            }
            .padding(DSSpacing.md)
        }
        .background(Color.dsBackground)
        .navigationTitle("城市剧情")
        .task { await reload() }
        .onAppear { Task { await reload() } }
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
            Text("城市剧情会在首次抵达后解锁，并需回到对应城市开展。当前城市始终排在最前。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, DSSpacing.xs)
    }

    private func chapterCard(_ chapter: CityStoryChapter) -> some View {
        let region = deps.regionCatalog.region(id: chapter.regionID)
        let isHere = profile?.currentRegionID == chapter.regionID
        let isUnlocked = isRegionUnlocked(chapter.regionID)
        let isCompleted = completed.contains(chapter.storyID)
        let accent = DSScenePalette.city(chapter.regionID).accent

        return HStack(spacing: DSSpacing.sm) {
            ZStack(alignment: .bottomLeading) {
                Image("home_mainline_\(chapter.regionID)")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 92, height: 108)
                    .clipped()
                LinearGradient(
                    colors: [.clear, .black.opacity(0.58)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                Text(region.map { flag($0.countryCode) } ?? "🌍")
                    .font(.title3)
                    .padding(8)
            }
            .frame(width: 92, height: 108)
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.inline, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(region?.nameZh ?? chapter.regionID)
                        .font(.caption.weight(.black))
                        .foregroundStyle(accent)
                    if isHere {
                        Text("当前城市")
                            .font(.system(size: 9, weight: .black))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .foregroundStyle(.white)
                            .background(accent, in: Capsule())
                    }
                }
                Text(chapter.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(chapter.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Label(
                    actionText(
                        isHere: isHere,
                        isUnlocked: isUnlocked,
                        isCompleted: isCompleted,
                        regionName: region?.nameZh
                    ),
                    systemImage: statusIcon(
                        isHere: isHere,
                        isUnlocked: isUnlocked,
                        isCompleted: isCompleted
                    )
                )
                .font(.caption.weight(.bold))
                .foregroundStyle(isHere ? accent : .secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(DSSpacing.sm)
        .background(Color.dsSurface)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
                .stroke(isHere ? accent.opacity(0.45) : Color.dsBorder, lineWidth: 1)
        }
        .opacity(isUnlocked ? 1 : 0.58)
        .contentShape(RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous))
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

    private func canOpen(_ chapter: CityStoryChapter) -> Bool {
        profile?.currentRegionID == chapter.regionID
    }

    private func isRegionUnlocked(_ regionID: String) -> Bool {
        guard let profile else { return false }
        return regionID == profile.currentRegionID || profile.unlockedRegionIDs.contains(regionID)
    }

    private func actionText(
        isHere: Bool,
        isUnlocked: Bool,
        isCompleted: Bool,
        regionName: String?
    ) -> String {
        if isHere {
            return isCompleted ? "可重温" : "开展剧情"
        }
        if isUnlocked {
            return "回到\(regionName ?? "这座城市")后开展"
        }
        return "首次抵达后解锁"
    }

    private func statusIcon(isHere: Bool, isUnlocked: Bool, isCompleted: Bool) -> String {
        if isCompleted { return "checkmark.circle.fill" }
        if isHere { return "play.circle.fill" }
        if isUnlocked { return "location.fill" }
        return "lock.fill"
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

    private func flag(_ code: String) -> String {
        code.uppercased().unicodeScalars.reduce(into: "") { result, scalar in
            if let value = Unicode.Scalar(0x1F1E6 + scalar.value - Unicode.Scalar("A").value) {
                result.unicodeScalars.append(value)
            }
        }
    }
}

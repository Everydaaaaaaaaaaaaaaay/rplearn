import DomainKit
import PersistenceKit
import SwiftUI

/// HomeFeature 依赖。
public struct HomeDependencies: Sendable {
    public let economyStore: EconomyStore
    public let storyProgress: StoryProgressStore
    public let regionCatalog: RegionCatalog

    public init(economyStore: EconomyStore, storyProgress: StoryProgressStore, regionCatalog: RegionCatalog) {
        self.economyStore = economyStore
        self.storyProgress = storyProgress
        self.regionCatalog = regionCatalog
    }
}

/// 主页 hub：当前地区卡片、主线剧情入口。活动/地图/票根夹入口在 2.3/2.4 补齐。
public struct HomeView: View {
    private let deps: HomeDependencies
    @State private var profile: UserProfileDTO?
    @State private var completedStories: Set<String> = []

    public init(deps: HomeDependencies) {
        self.deps = deps
    }

    private var currentRegion: Region? {
        profile.flatMap { deps.regionCatalog.region(id: $0.currentRegionID) }
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                regionCard
                mainlineSection
            }
            .padding(16)
        }
        .navigationTitle("主页")
        .task {
            await reload()
        }
        .refreshable {
            await reload()
        }
    }

    // MARK: - 当前地区

    @ViewBuilder
    private var regionCard: some View {
        if let region = currentRegion {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(regionFlag(region.countryCode))
                        .font(.system(size: 40))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(region.nameZh)
                            .font(.title2.bold())
                        Text("\(region.nameEn) · \(region.countryNameZh)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let profile {
                        Label("\(profile.coins)", systemImage: "circle.grid.2x1.fill")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.orange)
                    }
                }
                Text(region.taglineZh)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 100)
        }
    }

    // MARK: - 主线剧情

    @ViewBuilder
    private var mainlineSection: some View {
        if let region = currentRegion {
            let chapters = MainlineCatalog.chapters(forRegion: region.id)
            if !chapters.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("主线剧情")
                        .font(.headline)
                    ForEach(chapters) { chapter in
                        NavigationLink(value: chapter) {
                            chapterRow(chapter)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func chapterRow(_ chapter: MainlineChapter) -> some View {
        HStack(spacing: 12) {
            Image(systemName: completedStories.contains(chapter.storyID) ? "checkmark.seal.fill" : "book.pages")
                .font(.title3)
                .foregroundStyle(completedStories.contains(chapter.storyID) ? .green : Color.accentColor)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(chapter.title)
                    .font(.subheadline.weight(.semibold))
                Text(chapter.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.forward")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - 数据

    private func reload() async {
        profile = try? await deps.economyStore.profile()
        completedStories = (try? await deps.storyProgress.completedStoryIDs()) ?? []
    }

    private func regionFlag(_ countryCode: String) -> String {
        countryCode.unicodeScalars.reduce(into: "") { result, scalar in
            if let flagScalar = Unicode.Scalar(0x1F1E6 + scalar.value - Unicode.Scalar("A").value) {
                result.unicodeScalars.append(flagScalar)
            }
        }
    }
}

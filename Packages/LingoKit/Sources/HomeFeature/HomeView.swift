import DomainKit
import LLMKit
import PersistenceKit
import SwiftUI

/// HomeFeature 依赖。
public struct HomeDependencies: Sendable {
    public let economyStore: EconomyStore
    public let storyProgress: StoryProgressStore
    public let regionCatalog: RegionCatalog
    public let rosterStore: RosterStore
    public let chatStore: ChatStore
    public let llm: any LLMClient

    public init(
        economyStore: EconomyStore,
        storyProgress: StoryProgressStore,
        regionCatalog: RegionCatalog,
        rosterStore: RosterStore,
        chatStore: ChatStore,
        llm: any LLMClient
    ) {
        self.economyStore = economyStore
        self.storyProgress = storyProgress
        self.regionCatalog = regionCatalog
        self.rosterStore = rosterStore
        self.chatStore = chatStore
        self.llm = llm
    }
}

/// 主页导航目标（组合根映射到具体 Feature 页面，Feature 间零依赖）。
public enum HomeDestination: Hashable, Sendable {
    case map
    case ticketStubs
}

/// 主页 hub：当前地区卡片、活动偶遇、主线剧情、地图/票根夹入口。
public struct HomeView: View {
    private let deps: HomeDependencies
    private let encounterChatBuilder: @MainActor (CharacterDTO) -> AnyView
    @State private var profile: UserProfileDTO?
    @State private var completedStories: Set<String> = []

    public init(
        deps: HomeDependencies,
        encounterChatBuilder: @escaping @MainActor (CharacterDTO) -> AnyView
    ) {
        self.deps = deps
        self.encounterChatBuilder = encounterChatBuilder
    }

    private var currentRegion: Region? {
        profile.flatMap { deps.regionCatalog.region(id: $0.currentRegionID) }
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                regionCard
                entryGrid
                if let region = currentRegion {
                    EncounterSection(region: region, deps: deps, chatBuilder: encounterChatBuilder)
                }
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

    // MARK: - 功能入口

    private var entryGrid: some View {
        HStack(spacing: 12) {
            entryTile(destination: .map, title: "地图", subtitle: "去别的城市", systemImage: "map.fill", tint: .blue)
            entryTile(destination: .ticketStubs, title: "票根夹", subtitle: "旅行的记忆", systemImage: "ticket.fill", tint: .orange)
        }
    }

    private func entryTile(
        destination: HomeDestination,
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        NavigationLink(value: destination) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
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

import DesignSystem
import DomainKit
import PersistenceKit
import SwiftUI

/// 剧情二级入口：主线负责跨城推进，城市剧情承载每座城市的独立故事。
public struct StoryHubView: View {
    private let deps: HomeDependencies

    @State private var profile: UserProfileDTO?
    @State private var completed: Set<String> = []

    public init(deps: HomeDependencies) {
        self.deps = deps
    }

    private var journey: MainlineJourney {
        MainlineCatalog.journey(starterRegionID: profile?.starterRegionID)
    }

    private var currentRegion: Region? {
        profile.flatMap { deps.regionCatalog.region(id: $0.currentRegionID) }
    }

    private var completedMainlineCount: Int {
        journey.stops.filter { completed.contains($0.chapter.storyID) }.count
    }

    private var completedCityCount: Int {
        CityStoryCatalog.chapters.filter { completed.contains($0.storyID) }.count
    }

    private var unlockedCityCount: Int {
        guard let profile else { return 0 }
        let unlocked = Set(profile.unlockedRegionIDs + [profile.currentRegionID])
        return CityStoryCatalog.chapters.filter { unlocked.contains($0.regionID) }.count
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.lg) {
                intro

                NavigationLink(value: HomeDestination.mainline) {
                    categoryCard(
                        eyebrow: "出发之后",
                        title: "主线剧情",
                        detail: "从一次邀请出发，在五座城市参与一些具体的生活。",
                        progressText: "\(completedMainlineCount) / \(journey.stops.count) 站",
                        progress: Double(completedMainlineCount) / Double(journey.stops.count),
                        artworkName: "home_mainline_\(currentRegion?.id ?? journey.starterRegionID)",
                        tint: .dsSky
                    )
                }
                .buttonStyle(.pressableCard)
                .accessibilityIdentifier("story.mainline")
                .frame(maxWidth: .infinity)

                NavigationLink(value: HomeDestination.cityStories) {
                    categoryCard(
                        eyebrow: "抵达后解锁",
                        title: "城市剧情",
                        detail: "每座城市都有一段独立故事，在当地认识街区与生活。",
                        progressText: "\(completedCityCount) / \(CityStoryCatalog.chapters.count) 篇 · 已到访 \(unlockedCityCount) 城",
                        progress: Double(completedCityCount) / Double(CityStoryCatalog.chapters.count),
                        artworkName: "home_activity_\(currentRegion?.id ?? journey.starterRegionID)",
                        tint: .dsSunset
                    )
                }
                .buttonStyle(.pressableCard)
                .accessibilityIdentifier("story.cities")
                .frame(maxWidth: .infinity)
            }
            .padding(DSSpacing.md)
        }
        .background(Color.dsBackground)
        .navigationTitle("剧情")
        .task { await reload() }
        .onAppear { Task { await reload() } }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text("选择一段旅程")
                .font(.system(.title2, design: .rounded, weight: .bold))
            Text("主线决定旅程的方向，城市剧情记录你真正抵达过的地方。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func categoryCard(
        eyebrow: String,
        title: String,
        detail: String,
        progressText: String,
        progress: Double,
        artworkName: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            GeometryReader { proxy in
                ZStack(alignment: .bottomLeading) {
                    Image(artworkName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: 154)
                        .clipped()

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.72)],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(eyebrow.uppercased())
                            .font(.caption2.weight(.black))
                            .tracking(1)
                            .opacity(0.82)
                        Text(title)
                            .font(.system(.title2, design: .rounded, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(DSSpacing.md)
                }
                .frame(width: proxy.size.width, height: 154)
            }
            .frame(height: 154)
            .clipped()

            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, DSSpacing.md)

            HStack {
                Text(progressText)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.caption.bold())
                    .foregroundStyle(tint)
            }
            .padding(.horizontal, DSSpacing.md)

            ProgressView(value: progress)
                .tint(tint)
                .padding(.horizontal, DSSpacing.md)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, DSSpacing.md)
        .background(Color.dsSurface)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
                .stroke(Color.dsBorder, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous))
    }

    private func reload() async {
        async let loadedProfile = try? deps.economyStore.profile()
        async let loadedCompleted = try? deps.storyProgress.completedStoryIDs()
        profile = await loadedProfile
        completed = await loadedCompleted ?? []
    }
}

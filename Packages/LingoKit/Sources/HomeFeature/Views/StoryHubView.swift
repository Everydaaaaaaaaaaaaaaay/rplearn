import DesignSystem
import DomainKit
import PersistenceKit
import SwiftUI

/// 剧情二级入口：主线负责跨城推进，城市剧情承载每座城市的独立故事。
public struct StoryHubView: View {
    private let deps: HomeDependencies
    private let onPreview: (() -> Void)?

    @State private var profile: UserProfileDTO?
    @State private var completed: Set<String> = []

    public init(deps: HomeDependencies, onPreview: (() -> Void)? = nil) {
        self.deps = deps
        self.onPreview = onPreview
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

                if let onPreview {
                    Button(action: onPreview) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("出发之后 · 新版伦敦样章").font(.caption.weight(.semibold)).tracking(1)
                                .foregroundStyle(Color(red: 0.77, green: 0.62, blue: 0.37))
                            Text("空着的那把椅子").font(.title2.weight(.semibold))
                            Text("一个雨夜，一页没念过的文字，以及一个由你陪伴的决定。")
                                .font(.subheadline).foregroundStyle(.secondary)
                            HStack {
                                Text("日系演出 · 两次选择 · 独立本地进度").font(.caption)
                                Spacer()
                                Image(systemName: "arrow.right")
                            }
                        }.foregroundStyle(Color.primary).padding(22)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.dsSurface, in: RoundedRectangle(cornerRadius: 16))
                    }.buttonStyle(.pressableCard).accessibilityIdentifier("story.london.preview")
                }

                NavigationLink(value: HomeDestination.mainline) {
                    categoryCard(
                        eyebrow: "五城回声",
                        title: "主线剧情",
                        detail: "跟随初始伙伴跨越五座城市，推进共同的声音地图故事。",
                        progressText: "\(completedMainlineCount) / \(journey.stops.count) 站",
                        progress: Double(completedMainlineCount) / Double(journey.stops.count),
                        artworkName: "home_mainline_\(currentRegion?.id ?? journey.starterRegionID)",
                        tint: .dsSky
                    )
                }
                .buttonStyle(.pressableCard)
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

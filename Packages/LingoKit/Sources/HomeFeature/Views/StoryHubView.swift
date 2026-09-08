import DesignSystem
import DomainKit
import PersistenceKit
import SwiftUI

/// 剧情二级入口：主线承载五城长篇，城市剧情提供按机票渐进开放的独立故事。
public struct StoryHubView: View {
    private let deps: HomeDependencies

    @State private var profile: UserProfileDTO?
    @State private var completed: Set<String> = []
    @State private var cityUnlockProgress = CityStoryUnlockProgress(
        profile: nil,
        availableTickets: [],
        ticketStubs: []
    )

    public init(deps: HomeDependencies) {
        self.deps = deps
    }

    private var journey: MainlineJourney {
        MainlineCatalog.journey(starterRegionID: profile?.starterRegionID)
    }

    private var completedMainlineCount: Int {
        journey.stops.filter { completed.contains($0.chapter.storyID) }.count
    }

    private var completedCityCount: Int {
        CityStoryCatalog.chapters.filter { completed.contains($0.storyID) }.count
    }

    private var unlockedCityCount: Int {
        cityUnlockProgress.unlockedChapterCount
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.lg) {
                NavigationLink(value: HomeDestination.mainline) {
                    categoryCard(
                        eyebrow: "五城长篇",
                        title: "主线剧情",
                        detail: "五座城市串起同一段旅程。所有章节都能直接开始，按自己的节奏走到终章。",
                        progressText: "\(completedMainlineCount) / \(journey.stops.count) 章 · 全部开放",
                        progress: Double(completedMainlineCount) / Double(journey.stops.count),
                        artworkNames: MainlineCatalog.chapters.map {
                            DSCitySceneAssets.imageName(for: .messages, regionID: $0.regionID)
                        },
                        tint: .dsSky
                    )
                }
                .buttonStyle(.pressableCard)
                .accessibilityIdentifier("story.mainline")
                .frame(maxWidth: .infinity)

                NavigationLink(value: HomeDestination.cityStories) {
                    categoryCard(
                        eyebrow: "十五城短篇",
                        title: "城市剧情",
                        detail: "六篇生活故事即刻可读；每累计一张机票再开放三篇，三张即可读遍十五座城市。",
                        progressText: "\(completedCityCount) / \(CityStoryCatalog.chapters.count) 篇 · 已开放 \(unlockedCityCount) 篇",
                        progress: Double(completedCityCount) / Double(CityStoryCatalog.chapters.count),
                        artworkNames: CityStoryCatalog.chapters.map {
                            DSCitySceneAssets.imageName(for: .contacts, regionID: $0.regionID)
                        },
                        tint: .dsSunset
                    )
                }
                .buttonStyle(.pressableCard)
                .accessibilityIdentifier("story.cities")
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)
        }
        .background(Color.dsBackground)
        .navigationTitle("剧情")
        .task { await reload() }
        .onAppear { Task { await reload() } }
    }

    private func categoryCard(
        eyebrow: String,
        title: String,
        detail: String,
        progressText: String,
        progress: Double,
        artworkNames: [String],
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            GeometryReader { proxy in
                ZStack(alignment: .bottomLeading) {
                    artworkStrips(artworkNames, width: proxy.size.width)

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

    private func artworkStrips(_ artworkNames: [String], width: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(artworkNames.enumerated()), id: \.offset) { _, artworkName in
                Image(artworkName)
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width: width / CGFloat(max(artworkNames.count, 1)),
                        height: 154
                    )
                    .clipped()
            }
        }
        .frame(width: width, height: 154)
        .clipped()
        .accessibilityHidden(true)
    }

    private func reload() async {
        async let loadedProfile = try? deps.economyStore.profile()
        async let loadedCompleted = try? deps.storyProgress.completedStoryIDs()
        async let loadedTickets = try? deps.itemStore.unconsumedTickets()
        async let loadedStubs = try? deps.ticketStubStore.all()
        let resolvedProfile = await loadedProfile
        profile = resolvedProfile
        completed = await loadedCompleted ?? []
        cityUnlockProgress = CityStoryUnlockProgress(
            profile: resolvedProfile,
            availableTickets: await loadedTickets ?? [],
            ticketStubs: await loadedStubs ?? []
        )
    }
}

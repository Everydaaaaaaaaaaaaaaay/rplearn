import DesignSystem
import DomainKit
import PersistenceKit
import SwiftUI
import UIKit

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
        GeometryReader { geometry in
            ZStack {
                GeometryReader { scene in
                if let url = Bundle.main.url(forResource: "london_interior", withExtension: "jpg", subdirectory: "StoryArt")
                    ?? Bundle.main.url(forResource: "london_interior", withExtension: "jpg"),
                   let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: scene.size.width, height: scene.size.height).clipped()
                        .overlay { LinearGradient(colors: [.black.opacity(0.32), .clear, .black.opacity(0.18)],
                                                 startPoint: .top, endPoint: .bottom) }
                        .accessibilityHidden(true)
                } else { DSReadingPalette.canvas }
                }.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("五座城市，一路同行").font(.caption)
                            Text("出发之后").font(.system(.largeTitle, design: .serif, weight: .regular))
                        }.foregroundStyle(.white).padding(.top, 24).padding(.bottom, 100)
                        NavigationLink(value: HomeDestination.mainline) {
                            DSPaper(floating: true) {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("主线 · 五城长篇").font(.caption).foregroundStyle(DSReadingPalette.secondary)
                                    DSReadingRow("出发之后", symbol: "book.pages", value: "全部开放")
                                    Text("\(completedMainlineCount) / \(journey.stops.count) 章已完成")
                                        .font(.subheadline).foregroundStyle(DSReadingPalette.secondary)
                                    ProgressView(value: Double(completedMainlineCount), total: Double(journey.stops.count)).tint(DSReadingPalette.tint)
                                }
                            }
                        }.accessibilityIdentifier("story.mainline")
                        NavigationLink(value: HomeDestination.cityStories) {
                            DSPaper(floating: true) {
                                VStack(alignment: .leading, spacing: 12) {
                                    DSReadingRow("城市故事", symbol: "book.closed", value: "\(CityStoryCatalog.chapters.count) 座城市")
                                    Text("走进街区，也走进别人的一天。").font(.subheadline).foregroundStyle(DSReadingPalette.secondary)
                                    Text("已开放 \(unlockedCityCount) 篇 · 已完成 \(completedCityCount) 篇")
                                        .font(.caption).foregroundStyle(DSReadingPalette.secondary)
                                }
                            }
                        }.accessibilityIdentifier("story.cities")
                    }.buttonStyle(DSReadingPressStyle()).padding(.horizontal, 20).padding(.bottom, 20)
                        .frame(maxWidth: 620).frame(maxWidth: .infinity)
                }
            }
        }.navigationTitle("剧情").toolbarColorScheme(.dark, for: .navigationBar)
            .task { await reload() }.onAppear { Task { await reload() } }
    }

    private func reload() async {
        async let loadedProfile = try? deps.economyStore.profile()
        async let loadedCompleted = try? deps.storyProgress.completedStoryIDs()
        async let loadedTickets = try? deps.itemStore.unconsumedTickets()
        async let loadedStubs = try? deps.ticketStubStore.all()
        let resolvedProfile = await loadedProfile
        profile = resolvedProfile
        completed = DepartureStoryIdentity.catalogCompletionIDs(await loadedCompleted ?? [])
        cityUnlockProgress = CityStoryUnlockProgress(
            profile: resolvedProfile,
            availableTickets: await loadedTickets ?? [],
            ticketStubs: await loadedStubs ?? []
        )
    }
}

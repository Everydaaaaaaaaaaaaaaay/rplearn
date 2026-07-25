import DesignSystem
import DomainKit
import LLMKit
import PersistenceKit
import SwiftUI

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

public enum HomeDestination: Hashable, Sendable {
    case mainline
    case activities
}

/// 首页聚合 Hub：城市氛围、最近会话与两个核心探索入口。
public struct HomeView: View {
    private let deps: HomeDependencies
    private let chatBuilder: @MainActor (CharacterDTO) -> AnyView
    private let onOpenMessages: @MainActor () -> Void

    @State private var profile: UserProfileDTO?
    @State private var completedStories: Set<String> = []
    @State private var recentRows: [RecentChatRow] = []
    @State private var scrollOffset: CGFloat = 0

    public init(
        deps: HomeDependencies,
        chatBuilder: @escaping @MainActor (CharacterDTO) -> AnyView,
        onOpenMessages: @escaping @MainActor () -> Void
    ) {
        self.deps = deps
        self.chatBuilder = chatBuilder
        self.onOpenMessages = onOpenMessages
    }

    private var currentRegion: Region? {
        profile.flatMap { deps.regionCatalog.region(id: $0.currentRegionID) }
    }

    public var body: some View {
        ZStack {
            if let currentRegion {
                CityBackdropView(region: currentRegion, parallax: scrollOffset)
            } else {
                Color.dsBackground.ignoresSafeArea()
            }

            ScrollView {
                VStack(spacing: DSSpacing.md) {
                    cityHeader
                    recentChats
                    exploreSection
                }
                .padding(.horizontal, DSSpacing.md)
                .padding(.top, DSSpacing.xs)
                .padding(.bottom, DSSpacing.md)
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, newValue in
                scrollOffset = newValue
            }
            .refreshable { await reload() }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await reload() }
    }

    @ViewBuilder
    private var cityHeader: some View {
        if let region = currentRegion {
            HStack(spacing: DSSpacing.sm) {
                Text(flag(region.countryCode))
                    .font(.system(size: 28))
                VStack(alignment: .leading, spacing: 1) {
                    Text(region.nameZh)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                    Text(region.taglineZh)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: DSSpacing.xs)
                if let profile {
                    Label("\(profile.coins)", systemImage: "circle.grid.2x1.fill")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(Color.dsSunset, in: Capsule())
                }
            }
            .padding(DSSpacing.sm)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
                    .stroke(.white.opacity(0.25), lineWidth: 1)
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 64)
        }
    }

    private var recentChats: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack {
                Text("最近会话")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                Spacer()
                Button("查看全部 ›") { onOpenMessages() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.dsSky)
            }

            if recentRows.isEmpty {
                VStack(spacing: DSSpacing.xs) {
                    Image(systemName: "bubble.left.and.sparkles")
                        .font(.title2)
                        .foregroundStyle(Color.dsSky)
                    Text("伙伴正在等你打招呼")
                        .font(.subheadline.weight(.semibold))
                    Text("完成开场剧情后，最近的聊天会出现在这里")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DSSpacing.lg)
            } else {
                ForEach(Array(recentRows.prefix(3).enumerated()), id: \.element.id) { index, row in
                    NavigationLink {
                        chatBuilder(row.character)
                    } label: {
                        HStack(spacing: DSSpacing.sm) {
                            AvatarBadge(name: row.character.card.name, size: 46)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.character.card.name)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.primary)
                                Text(row.summary.lastMessageText.isEmpty ? "打个招呼吧 👋" : row.summary.lastMessageText)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 8) {
                                Text(row.summary.lastMessageAt, format: .relative(presentation: .named))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                if index == 0 {
                                    Circle()
                                        .fill(Color.dsDanger)
                                        .frame(width: 8, height: 8)
                                }
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < min(recentRows.count, 3) - 1 {
                        Divider().padding(.leading, 58)
                    }
                }
            }
        }
        .dsCard()
    }

    @ViewBuilder
    private var exploreSection: some View {
        if let region = currentRegion {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                Text("探索\(region.nameZh)")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(.primary)

                NavigationLink(value: HomeDestination.mainline) {
                    ExploreCard(
                        title: "主线剧情",
                        subtitle: "\(completedCount(for: region)) / \(chapterCount(for: region)) 章",
                        icon: "book.pages.fill",
                        colors: [Color.dsSky, Color.dsCyan],
                        progress: chapterCount(for: region) == 0
                            ? 0
                            : Double(completedCount(for: region)) / Double(chapterCount(for: region))
                    )
                }
                .buttonStyle(.pressableCard)

                NavigationLink(value: HomeDestination.activities) {
                    ExploreCard(
                        title: "城市活动",
                        subtitle: "参与活动，认识新朋友",
                        icon: "figure.walk.motion",
                        colors: [Color.dsSunset, Color.dsWarning],
                        progress: nil
                    )
                }
                .buttonStyle(.pressableCard)
            }
        }
    }

    private func completedCount(for region: Region) -> Int {
        MainlineCatalog.chapters(forRegion: region.id).filter { completedStories.contains($0.storyID) }.count
    }

    private func chapterCount(for region: Region) -> Int {
        MainlineCatalog.chapters(forRegion: region.id).count
    }

    private func reload() async {
        async let loadedProfile = try? deps.economyStore.profile()
        async let loadedCompleted = try? deps.storyProgress.completedStoryIDs()
        async let loadedFriends = try? deps.rosterStore.friends()
        async let loadedSummaries = try? deps.chatStore.conversationSummaries()

        profile = await loadedProfile
        completedStories = await loadedCompleted ?? []
        let friends = await loadedFriends ?? []
        let summaries = await loadedSummaries ?? []
        let friendsByID = Dictionary(uniqueKeysWithValues: friends.map { ($0.id, $0) })
        recentRows = summaries.compactMap { summary in
            friendsByID[summary.characterID].map { RecentChatRow(character: $0, summary: summary) }
        }
    }

    private func flag(_ countryCode: String) -> String {
        countryCode.uppercased().unicodeScalars.reduce(into: "") { result, scalar in
            if let value = Unicode.Scalar(0x1F1E6 + scalar.value - Unicode.Scalar("A").value) {
                result.unicodeScalars.append(value)
            }
        }
    }
}

private struct RecentChatRow: Identifiable {
    let character: CharacterDTO
    let summary: ConversationSummaryDTO
    var id: UUID { summary.id }
}

private struct ExploreCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let colors: [Color]
    let progress: Double?

    var body: some View {
        HStack(spacing: DSSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .bold))
                .frame(width: 54, height: 54)
                .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: DSRadius.inline))
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text(title)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                Text(subtitle)
                    .font(.subheadline)
                    .opacity(0.88)
                if let progress {
                    ProgressView(value: progress)
                        .tint(.white)
                        .background(.black.opacity(0.12), in: Capsule())
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.headline)
                .padding(10)
                .background(.white, in: Circle())
                .foregroundStyle(colors[0])
        }
        .foregroundStyle(.white)
        .padding(DSSpacing.md)
        .background(
            LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing),
            in: RoundedRectangle(cornerRadius: DSRadius.hero, style: .continuous)
        )
        .shadow(color: colors[0].opacity(0.24), radius: 10, y: 5)
    }
}

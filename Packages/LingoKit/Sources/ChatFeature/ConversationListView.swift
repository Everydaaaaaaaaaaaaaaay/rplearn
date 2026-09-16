import DomainKit
import DesignSystem
import CoreKit
import Foundation
import PersistenceKit
import SwiftUI

/// 旅途通讯列表：保留原生搜索、导航与侧滑操作，突出伙伴关系和会话状态。
public struct ConversationListView: View {
    private let deps: ChatDependencies
    private let reloadToken: Int

    @State private var rows: [ConversationListRow] = []
    @State private var isLoading = true
    @State private var isVisible = false
    @State private var reloadGeneration = UUID()
    @State private var searchText = ""
    @State private var currentRegionID = "london"
    @State private var selectedConversationID: UUID?
    @AppStorage private var persistedUnreadCount: Int

    public init(accountID: UUID, deps: ChatDependencies, reloadToken: Int = 0) {
        _persistedUnreadCount = AppStorage(
            wrappedValue: 0,
            ProactiveMessagePreferences.unreadCountKey(for: accountID)
        )
        self.deps = deps
        self.reloadToken = reloadToken
    }

    private var visibleRows: [ConversationListRow] {
        let searched = searchText.isEmpty
            ? rows
            : rows.filter { $0.character.card.name.localizedCaseInsensitiveContains(searchText) }
        return searched.sorted {
            let lhsPinned = $0.summary?.isPinned ?? false
            let rhsPinned = $1.summary?.isPinned ?? false
            if lhsPinned != rhsPinned { return lhsPinned }
            switch ($0.summary, $1.summary) {
            case (.some(let lhs), .some(let rhs)):
                return lhs.lastMessageAt > rhs.lastMessageAt
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return $0.friendOrder < $1.friendOrder
            }
        }
    }

    public var body: some View {
        searchAdaptedContent
            .navigationTitle("信息")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $selectedConversationID) { characterID in
                conversationDestination(characterID: characterID)
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            // task 会在列表真正重新出现时自动重启；不要从根视图跨页面改变 reloadToken，
            // 否则隐藏在聊天页下方的动态行可能改写 NavigationLink 的来源。
            .onAppear { isVisible = true }
            .onDisappear { isVisible = false }
            .task(id: reloadToken) { await reload() }
            .onReceive(NotificationCenter.default.publisher(for: .roleplayConversationDidChange)) { _ in
                guard isVisible else { return }
                Task { await reload() }
            }
            .refreshable { await reload() }
            .onReceive(NotificationCenter.default.publisher(for: .npcAvatarDidChange)) { _ in
                Task { await reload() }
            }
            .onReceive(NotificationCenter.default.publisher(for: ConversationReadState.didChange)) { _ in
                Task { await reload() }
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .rosterFavoriteDidChange)
            ) { notification in
                guard let characterID = notification.object as? UUID,
                      let isFavorite = notification.userInfo?["isFavorite"] as? Bool else { return }
                applyFavoriteChange(characterID: characterID, isFavorite: isFavorite)
            }
            .overlay {
                if isLoading {
                    ProgressView()
                        .tint(Color.dsSceneTextPrimary)
                        .padding(DSSpacing.lg)
                        .dsSceneGlass(
                            radius: DSRadius.card,
                            tint: Color.white.opacity(0.06),
                            legibility: .enhanced
                        )
                }
            }
    }

    @ViewBuilder
    private var searchAdaptedContent: some View {
        if #available(iOS 26.0, *), DSPlatformVisualPolicy.usesLiquidGlass {
            sceneContent
                .dsSceneSearch(text: $searchText, title: "信息", prompt: "搜索信息")
        } else {
            sceneContent
                .safeAreaInset(edge: .top, spacing: 0) {
                    DSLegacySceneSearchField(text: $searchText, prompt: "搜索信息")
                        .padding(.horizontal, DSSpacing.md)
                        .padding(.top, 4)
                        .padding(.bottom, DSSpacing.sm)
                }
        }
    }

    private var sceneContent: some View {
        ZStack {
            DSSceneBackdrop(
                imageName: DSCitySceneAssets.imageName(
                    for: .messages,
                    regionID: currentRegionID
                ),
                tone: .cool
            )

            if rows.isEmpty && !isLoading {
                emptyState
            } else {
                List {
                    if visibleRows.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                            .padding(DSSpacing.xl)
                            .foregroundStyle(Color.dsSceneTextPrimary)
                            .dsSceneGlass(
                                tint: Color.white.opacity(0.06),
                                legibility: .enhanced
                            )
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(visibleRows) { row in
                            Button {
                                if let summary = row.summary {
                                    markRead(summary)
                                }
                                selectedConversationID = row.id
                            } label: {
                                rowLabel(row)
                                    .padding(.horizontal, DSSpacing.md)
                                    .padding(.vertical, DSSpacing.sm)
                                    .dsSceneGlass(
                                        tint: Color.white.opacity(0.06),
                                        interactive: true,
                                        legibility: .enhanced
                                    )
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(
                                EdgeInsets(
                                    top: DSSpacing.xs / 2,
                                    leading: DSSpacing.md,
                                    bottom: DSSpacing.xs / 2,
                                    trailing: DSSpacing.md
                                )
                            )
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                if let conversationID = row.summary?.conversationID {
                                    Button {
                                        togglePinned(conversationID)
                                    } label: {
                                        Label(
                                            row.summary?.isPinned == true
                                                ? "取消置顶"
                                                : "置顶",
                                            systemImage: "pin.fill"
                                        )
                                    }
                                    .tint(.dsSky)
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                if let summary = row.summary {
                                    Button {
                                        markRead(summary)
                                    } label: {
                                        Label("标记已读", systemImage: "envelope.open.fill")
                                    }
                                    .tint(.dsCyan)
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .listSectionSpacing(DSSpacing.xs)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
        }
    }

    private func rowLabel(_ row: ConversationListRow) -> some View {
        let unreadCount = unreadCount(row)
        let unread = unreadCount > 0
        let pinned = row.summary?.isPinned ?? false

        return HStack(spacing: DSSpacing.sm) {
            ZStack(alignment: .topTrailing) {
                AvatarBadge(
                    name: row.character.displayName,
                    size: 54,
                    imageName: row.character.card.avatarAssetName,
                    remoteURL: row.character.card.avatarRemoteURL.flatMap(URL.init(string:)),
                    usesPendingPlaceholder: true
                )
                    .accessibilityHidden(true)
                if unread {
                    Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .padding(.horizontal, 5)
                        .frame(minWidth: 19, minHeight: 19)
                        .background(Color.dsDanger, in: Capsule())
                        .overlay { Capsule().stroke(Color.dsSurface, lineWidth: 2) }
                        .offset(x: 5, y: -4)
                        .accessibilityLabel("\(unreadCount) 条未读")
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(row.character.displayName)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Color.dsSceneTextPrimary)
                        .lineLimit(1)

                    if row.character.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.dsSunset)
                            .accessibilityLabel("特别关心")
                    }

                    if pinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.dsSkyDeep)
                            .accessibilityLabel("已置顶")
                    }

                    Spacer()

                    if let summary = row.summary {
                        Text(smartTime(summary.lastMessageAt))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Color.dsSceneTextTertiary)
                    }
                }

                Text(row.summary.map(summaryText) ?? "打个招呼吧 👋")
                    .font(.callout.weight(.regular))
                    .foregroundStyle(Color.dsSceneTextTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    @ViewBuilder
    private func conversationDestination(characterID: UUID) -> some View {
        if let character = rows.first(where: { $0.id == characterID })?.character {
            ChatView(character: character, deps: deps)
                .onDisappear {
                    Task { await reload() }
                }
        } else {
            ContentUnavailableView("联系人不存在", systemImage: "person.crop.circle.badge.questionmark")
        }
    }

    private var emptyState: some View {
        VStack(spacing: DSSpacing.lg) {
            ZStack {
                Circle()
                    .fill(Color.dsSky.opacity(0.1))
                    .frame(width: 116, height: 116)
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 42, weight: .black))
                    .foregroundStyle(Color.dsSky.gradient)
                    .rotationEffect(.degrees(-8))
            }

            VStack(spacing: DSSpacing.xs) {
                Text("通讯录还在等第一位旅伴")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.dsSceneTextPrimary)
                Text("完成开场剧情后，你认识的伙伴和消息会出现在这里")
                    .font(.subheadline)
                    .foregroundStyle(Color.dsSceneTextSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(DSSpacing.xl)
        .frame(maxWidth: 340)
        .dsSceneGlass(
            tint: Color.white.opacity(0.06),
            legibility: .enhanced
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DSSpacing.xl)
    }

    private func unreadCount(_ row: ConversationListRow) -> Int {
        row.summary?.unreadCount ?? 0
    }

    private func summaryText(_ summary: ConversationSummaryDTO) -> String {
        switch summary.lastMessageKind {
        case .voice: "[语音]"
        case .quiz: "[小测验]"
        default: summary.lastMessageText.isEmpty ? "打个招呼吧 👋" : summary.lastMessageText
        }
    }

    private func applyFavoriteChange(characterID: UUID, isFavorite: Bool) {
        guard let index = rows.firstIndex(where: { $0.character.id == characterID }) else {
            return
        }
        let currentRow = rows[index]
        var character = currentRow.character
        character.isFavorite = isFavorite
        rows[index] = ConversationListRow(
            character: character,
            friendOrder: currentRow.friendOrder,
            summary: currentRow.summary
        )
    }

    private func smartTime(_ date: Date) -> String {
        ConversationTimestampFormatter.string(for: date)
    }

    private func reload() async {
        let generation = UUID()
        reloadGeneration = generation
        defer { if reloadGeneration == generation { isLoading = false } }
        async let loadedProfile = try? deps.economyStore.profile()
        async let loadedFriends = deps.rosterStore.friends()
        async let loadedSummaries = deps.chatStore.conversationSummaries()
        let profile = await loadedProfile
        do {
            let (friends, summaries) = try await (loadedFriends, loadedSummaries)
            guard !Task.isCancelled, reloadGeneration == generation else { return }
            if let profile { currentRegionID = profile.currentRegionID }
            rows = ConversationListProjection.rows(friends: friends, summaries: summaries)
            updateUnreadCount()
        } catch {
            // 下拉刷新可重试；不以错误页打断导航。
        }
    }

    private func updateUnreadCount() {
        persistedUnreadCount = rows.reduce(into: 0) { total, row in
            guard let summary = row.summary else { return }
            total += summary.unreadCount
        }
    }

    private func markRead(_ summary: ConversationSummaryDTO) {
        updateSummary(summary.conversationID) { value in
            value.lastReadAt = max(value.lastReadAt ?? .distantPast, value.lastMessageAt)
        }
        updateUnreadCount()
        Task {
            try? await deps.chatStore.markRead(
                conversationID: summary.conversationID,
                at: summary.lastMessageAt
            )
            ConversationReadState.notifyChange()
        }
    }

    private func togglePinned(_ conversationID: UUID) {
        guard let current = rows.compactMap(\.summary).first(where: {
            $0.conversationID == conversationID
        }) else { return }
        let next = !current.isPinned
        updateSummary(conversationID) { $0.isPinned = next }
        Task {
            try? await deps.chatStore.setPinned(conversationID: conversationID, isPinned: next)
            ConversationReadState.notifyChange()
        }
    }

    private func updateSummary(
        _ conversationID: UUID,
        mutate: (inout ConversationSummaryDTO) -> Void
    ) {
        guard let index = rows.firstIndex(where: {
            $0.summary?.conversationID == conversationID
        }), var summary = rows[index].summary else { return }
        mutate(&summary)
        let row = rows[index]
        rows[index] = ConversationListRow(
            character: row.character,
            friendOrder: row.friendOrder,
            summary: summary
        )
    }
}

enum ConversationTimestampFormatter {
    static func string(
        for date: Date,
        relativeTo now: Date = .now,
        calendar: Calendar = .current
    ) -> String {
        if abs(now.timeIntervalSince(date)) <= 60 {
            return "刚刚"
        }

        if calendar.isDate(date, inSameDayAs: now) {
            return date.formatted(date: .omitted, time: .shortened)
        }

        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "昨天"
        }

        return date.formatted(.dateTime.month().day())
    }
}

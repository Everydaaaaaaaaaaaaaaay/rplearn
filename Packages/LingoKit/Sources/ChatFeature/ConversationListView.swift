import DomainKit
import DesignSystem
import CoreKit
import Foundation
import PersistenceKit
import SwiftUI

/// 信息页：白色主基调、城市卡通明信片、糖果色厚卡片会话行。
/// 保留置顶/已读侧滑、长按菜单、搜索与未读总数发布。
public struct ConversationListView: View {
    private enum Filter: Hashable {
        case all
        case unread
        case favorites
    }

    private let deps: ChatDependencies
    private let reloadToken: Int
    private let resetToken: Int
    private struct ReloadKey: Hashable {
        let token: Int
        let notificationRevision: Int
        let visible: Bool
    }

    @State private var rows: [ConversationListRow] = []
    @State private var isLoading = true
    @State private var isVisible = false
    @State private var hasEntered = false
    @State private var reloadGeneration = UUID()
    @State private var notificationRevision = 0
    @State private var searchText = ""
    @State private var filter: Filter = .all
    @State private var currentRegionID = "london"
    @State private var selectedConversationID: UUID?
    @State private var hasPublishedUnreadCount = false
    @AppStorage private var persistedUnreadCount: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(accountID: UUID, deps: ChatDependencies, reloadToken: Int = 0, resetToken: Int = 0) {
        _persistedUnreadCount = AppStorage(
            wrappedValue: 0,
            ProactiveMessagePreferences.unreadCountKey(for: accountID)
        )
        self.deps = deps
        self.reloadToken = reloadToken
        self.resetToken = resetToken
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool { !normalizedSearchText.isEmpty }

    private var visibleRows: [ConversationListRow] {
        if isSearching {
            return rows.filter { $0.character.card.name.localizedCaseInsensitiveContains(normalizedSearchText)
                || $0.character.displayName.localizedCaseInsensitiveContains(normalizedSearchText) }
        }
        switch filter {
        case .all: return rows
        case .unread: return rows.filter { unreadCount($0) > 0 }
        case .favorites: return rows.filter(\.character.isFavorite)
        }
    }

    private var unreadConversationCount: Int {
        rows.reduce(0) { $0 + (unreadCount($1) > 0 ? 1 : 0) }
    }

    private var totalUnreadCount: Int {
        rows.reduce(0) { $0 + unreadCount($1) }
    }

    private var motion: Animation {
        Puff.Motion.resolve(Puff.Motion.bouncy, reduceMotion: reduceMotion)
    }

    public var body: some View {
        pageContent
            .puffPageHeader(
                title: "信息",
                searchText: $searchText,
                searchPrompt: "搜索信息",
                resetToken: resetToken
            )
            .navigationTitle("信息")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $selectedConversationID) { characterID in
                conversationDestination(characterID: characterID)
            }
            // task 会在列表真正重新出现时自动重启；不要从根视图跨页面改变 reloadToken，
            // 否则隐藏在聊天页下方的动态行可能改写 NavigationLink 的来源。
            .onAppear { isVisible = true }
            .onDisappear { isVisible = false }
            .task(id: ReloadKey(token: reloadToken, notificationRevision: notificationRevision, visible: isVisible)) {
                if isVisible { await reload() }
            }
            .onChange(of: resetToken) {
                selectedConversationID = nil
                searchText = ""
                filter = .all
            }
            .onReceive(NotificationCenter.default.publisher(for: .roleplayConversationDidChange)) { _ in
                guard isVisible else { return }
                notificationRevision += 1
            }
            .onReceive(NotificationCenter.default.publisher(for: .rosterContactDidChange)) { _ in
                guard isVisible else { return }
                notificationRevision += 1
            }
            .onReceive(NotificationCenter.default.publisher(for: .npcAvatarDidChange)) { _ in
                guard isVisible else { return }
                notificationRevision += 1
            }
            .onReceive(NotificationCenter.default.publisher(for: ConversationReadState.didChange)) { _ in
                guard isVisible else { return }
                notificationRevision += 1
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .rosterFavoriteDidChange)
            ) { notification in
                guard let characterID = notification.object as? UUID,
                      let isFavorite = notification.userInfo?["isFavorite"] as? Bool else { return }
                applyFavoriteChange(characterID: characterID, isFavorite: isFavorite)
            }
    }

    @ViewBuilder
    private var pageContent: some View {
        ZStack {
            Puff.Palette.page.ignoresSafeArea()

            if rows.isEmpty && isLoading {
                PuffLoadingDots()
                    .transition(.opacity)
            } else if rows.isEmpty {
                ScrollView {
                    PuffEmptyState("还没有消息", mood: .sleepy)
                    .padding(.top, 80)
                    .frame(maxWidth: .infinity)
                    .puffEntrance(index: 0, isShown: hasEntered)
                }
                .refreshable { await reload() }
            } else {
                conversationList
            }
        }
        .animation(Puff.Motion.resolve(Puff.Motion.gentle, reduceMotion: reduceMotion), value: rows.isEmpty)
    }

    private var conversationList: some View {
        List {
            if !isSearching {
                postcard
                    .puffEntrance(index: 0, isShown: hasEntered)
                    .listRowInsets(EdgeInsets(top: 2, leading: Puff.Space.m, bottom: Puff.Space.xs, trailing: Puff.Space.m))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .transition(.puffDrop)

                PuffFilterBar(selection: $filter, options: [
                    .init(.all, title: "全部"),
                    .init(.unread, title: "未读", systemImage: "envelope.fill", count: unreadConversationCount),
                    .init(.favorites, title: "特别关心", systemImage: "star.fill"),
                ])
                .puffEntrance(index: 1, isShown: hasEntered)
                .listRowInsets(EdgeInsets(top: Puff.Space.xxs, leading: 0, bottom: Puff.Space.xxs, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if visibleRows.isEmpty {
                filteredEmptyState
                    .frame(maxWidth: .infinity)
                    .listRowInsets(EdgeInsets(top: Puff.Space.l, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .transition(.puffDrop)
            } else {
                ForEach(Array(visibleRows.enumerated()), id: \.element.id) { index, row in
                    conversationRow(row)
                        .puffEntrance(index: index + 2, isShown: hasEntered)
                        .listRowInsets(EdgeInsets(top: 5, leading: Puff.Space.m, bottom: 5, trailing: Puff.Space.m))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
        .contentMargins(.bottom, Puff.Space.l, for: .scrollContent)
        .refreshable { await reload() }
    }

    // MARK: - 明信片

    private var postcard: some View {
        PuffSceneCard(regionID: currentRegionID, viewport: .west, sceneHeight: 150, isActive: isVisible) {
            TimelineView(.everyMinute) { context in
                HStack(spacing: Puff.Space.s) {
                    VStack(alignment: .leading, spacing: 4) {
                        PuffTag(
                            "\(PuffCity.nameZh(for: currentRegionID)) · \(PuffCity.localTime(for: currentRegionID, at: context.date))",
                            systemImage: "location.fill",
                            candy: .sky
                        )
                        Text("\(PuffCity.greeting(for: currentRegionID, at: context.date))！")
                            .font(.puff(.title2, Puff.Weight.display))
                            .foregroundStyle(Puff.Palette.ink)
                    }
                    Spacer(minLength: 0)
                    mailbox
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// 有未读时是一只会跳的粉色信封，全部读完变成绿色对勾。
    private var mailbox: some View {
        let hasUnread = totalUnreadCount > 0
        let candy: PuffCandy = hasUnread ? .bubblegum : .mint
        return Image(systemName: hasUnread ? "envelope.fill" : "checkmark")
            .font(.system(size: 24, weight: Puff.Weight.icon, design: .rounded))
            .foregroundStyle(candy.deep)
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.bounce, value: totalUnreadCount)
            .frame(width: 58, height: 58)
            .background(candy.wash, in: Circle())
            .overlay(alignment: .topTrailing) {
                if hasUnread {
                    PuffCountBadge(totalUnreadCount)
                        .offset(x: 6, y: -4)
                        .transition(.puffPop)
                }
            }
            .animation(Puff.Motion.resolve(Puff.Motion.pop, reduceMotion: reduceMotion), value: hasUnread)
            .accessibilityHidden(true)
    }

    // MARK: - 会话行

    private func conversationRow(_ row: ConversationListRow) -> some View {
        let unread = unreadCount(row) > 0
        let pinned = row.summary?.isPinned ?? false
        return Button {
            if let summary = row.summary {
                markRead(summary)
            }
            selectedConversationID = row.id
        } label: {
            rowLabel(row)
        }
        .buttonStyle(PuffCardButtonStyle(
            radius: Puff.Radius.large,
            border: unread ? PuffCandy.sky.base.opacity(0.45) : Puff.Palette.line,
            lip: unread ? PuffCandy.sky.base.opacity(0.32) : Puff.Palette.lip
        ))
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: Puff.Radius.large, style: .continuous))
        .contextMenu {
            if let summary = row.summary {
                Button {
                    togglePinned(summary.conversationID)
                } label: {
                    Label(pinned ? "取消置顶" : "置顶", systemImage: pinned ? "pin.slash" : "pin")
                }
                if unread {
                    Button {
                        markRead(summary)
                    } label: {
                        Label("标记已读", systemImage: "envelope.open")
                    }
                }
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if let conversationID = row.summary?.conversationID {
                Button {
                    togglePinned(conversationID)
                } label: {
                    Label(pinned ? "取消置顶" : "置顶", systemImage: "pin.fill")
                }
                .tint(PuffCandy.grape.base)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if let summary = row.summary {
                Button {
                    markRead(summary)
                } label: {
                    Label("标记已读", systemImage: "envelope.open.fill")
                }
                .tint(PuffCandy.sky.base)
            }
        }
    }

    private func rowLabel(_ row: ConversationListRow) -> some View {
        let unreadCount = unreadCount(row)
        let unread = unreadCount > 0
        let pinned = row.summary?.isPinned ?? false

        return HStack(spacing: Puff.Space.s) {
            PuffAvatar(
                name: row.character.displayName,
                size: 58,
                imageName: row.character.card.avatarAssetName,
                remoteURL: row.character.card.avatarRemoteURL.flatMap(URL.init(string:))
            )

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(row.character.displayName)
                        .font(.puff(.headline, Puff.Weight.title))
                        .foregroundStyle(Puff.Palette.ink)
                        .lineLimit(1)

                    if row.character.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 12, weight: Puff.Weight.icon))
                            .foregroundStyle(PuffCandy.sunny.base)
                            .transition(.puffPop)
                            .accessibilityLabel("特别关心")
                    }

                    if pinned {
                        PuffTag("置顶", systemImage: "pin.fill", candy: .grape)
                            .transition(.puffPop)
                    }

                    Spacer(minLength: Puff.Space.xxs)

                    if let summary = row.summary {
                        Text(smartTime(summary.lastMessageAt))
                            .font(.puff(.caption, Puff.Weight.label))
                            .monospacedDigit()
                            .foregroundStyle(unread ? PuffCandy.sky.deep : Puff.Palette.inkFaint)
                    }
                }

                HStack(spacing: Puff.Space.xs) {
                    previewText(row, unread: unread)
                    Spacer(minLength: Puff.Space.xxs)
                    if unread {
                        PuffCountBadge(unreadCount)
                            .transition(.puffPop)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, Puff.Space.s)
        .animation(Puff.Motion.resolve(Puff.Motion.pop, reduceMotion: reduceMotion), value: unreadCount)
        .animation(Puff.Motion.resolve(Puff.Motion.pop, reduceMotion: reduceMotion), value: pinned)
        .animation(Puff.Motion.resolve(Puff.Motion.pop, reduceMotion: reduceMotion), value: row.character.isFavorite)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func previewText(_ row: ConversationListRow, unread: Bool) -> some View {
        let style: Font = unread ? .puff(.subheadline, Puff.Weight.label) : .puff(.subheadline, Puff.Weight.body)
        let color: Color = unread ? Puff.Palette.ink : Puff.Palette.inkSoft
        if row.summary?.lastMessageKind == .voice {
            Label("语音消息", systemImage: "waveform")
                .font(style)
                .foregroundStyle(color)
                .lineLimit(1)
        } else {
            Text(row.summary.map(summaryText) ?? "打个招呼吧 👋")
                .font(style)
                .foregroundStyle(color)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    @ViewBuilder
    private var filteredEmptyState: some View {
        if isSearching {
            PuffEmptyState("没有找到“\(normalizedSearchText)”", mood: .curious)
        } else if filter == .unread {
            PuffEmptyState("没有未读消息", mood: .happy)
        } else {
            PuffEmptyState("还没有特别关心", mood: .curious)
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

    private func unreadCount(_ row: ConversationListRow) -> Int {
        row.summary?.unreadCount ?? 0
    }

    private func summaryText(_ summary: ConversationSummaryDTO) -> String {
        summary.lastMessageText.isEmpty ? "打个招呼吧 👋" : summary.lastMessageText
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
        defer {
            if reloadGeneration == generation {
                withAnimation(Puff.Motion.resolve(Puff.Motion.gentle, reduceMotion: reduceMotion)) {
                    isLoading = false
                }
                startEntranceIfNeeded()
            }
        }
        async let loadedProfile = try? deps.economyStore.profile()
        async let loadedFriends = deps.rosterStore.friends()
        async let loadedSummaries = deps.chatStore.conversationSummaries()
        let profile = await loadedProfile
        do {
            let (friends, summaries) = try await (loadedFriends, loadedSummaries)
            guard !Task.isCancelled, reloadGeneration == generation else { return }
            if let profile { currentRegionID = profile.currentRegionID }
            let loadedRows = ConversationListProjection.rows(friends: friends, summaries: summaries)
            if rows != loadedRows {
                withAnimation(hasEntered ? motion : nil) { rows = loadedRows }
            }
            updateUnreadCount()
        } catch {
            // 下拉刷新可重试；不以错误页打断导航。
        }
    }

    /// 先以隐藏状态渲染首屏，再在下一帧触发逐行弹入。
    private func startEntranceIfNeeded() {
        guard !hasEntered else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(40))
            hasEntered = true
        }
    }

    private func updateUnreadCount() {
        let count = rows.reduce(into: 0) { total, row in
            guard let summary = row.summary else { return }
            total += summary.unreadCount
        }
        if !hasPublishedUnreadCount || persistedUnreadCount != count {
            // Publish the first loaded snapshot, even when it matches the default zero.
            persistedUnreadCount = count
            hasPublishedUnreadCount = true
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
        Haptics.impact(.light)
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
        var updated = rows
        updated[index] = ConversationListRow(
            character: row.character,
            friendOrder: row.friendOrder,
            summary: summary
        )
        withAnimation(motion) {
            rows = ConversationListProjection.sorted(updated)
        }
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

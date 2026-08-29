import DesignSystem
import PersistenceKit
import SwiftUI

/// 旅途通讯列表：保留原生搜索、导航与侧滑操作，突出伙伴关系和会话状态。
public struct ConversationListView: View {
    private let deps: ChatDependencies
    private let reloadToken: Int

    @State private var rows: [ConversationListRow] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var isSearchPresented = false
    @State private var stateRevision = 0
    @State private var currentRegionID = "london"
    @State private var selectedConversationID: UUID?
    @AppStorage("lingotrip.unread.count") private var persistedUnreadCount = 0

    public init(deps: ChatDependencies, reloadToken: Int = 0) {
        self.deps = deps
        self.reloadToken = reloadToken
    }

    private var visibleRows: [ConversationListRow] {
        let searched = searchText.isEmpty
            ? rows
            : rows.filter { $0.character.card.name.localizedCaseInsensitiveContains(searchText) }
        return searched.sorted {
            let lhsPinned = $0.summary.map { ConversationReadState.isPinned($0.conversationID) } ?? false
            let rhsPinned = $1.summary.map { ConversationReadState.isPinned($0.conversationID) } ?? false
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
                                    ConversationReadState.markRead(
                                        conversationID: summary.conversationID,
                                        at: summary.lastMessageAt
                                    )
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
                                        ConversationReadState.togglePinned(conversationID)
                                        stateRevision += 1
                                    } label: {
                                        Label(
                                            ConversationReadState.isPinned(conversationID)
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
                                        ConversationReadState.markRead(
                                            conversationID: summary.conversationID,
                                            at: summary.lastMessageAt
                                        )
                                        stateRevision += 1
                                        updateUnreadCount()
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
        .navigationTitle("信息")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedConversationID) { characterID in
            conversationDestination(characterID: characterID)
        }
        .searchable(
            text: $searchText,
            isPresented: $isSearchPresented,
            placement: .toolbar,
            prompt: "搜索信息"
        )
        .dsCompactSearchToolbar()
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        // task 会在列表真正重新出现时自动重启；不要从根视图跨页面改变 reloadToken，
        // 否则隐藏在聊天页下方的动态行可能改写 NavigationLink 的来源。
        .task(id: reloadToken) { await reload() }
        .refreshable { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: ConversationReadState.didChange)) { _ in
            stateRevision += 1
            updateUnreadCount()
        }
        .onChange(of: stateRevision) { updateUnreadCount() }
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

    private func rowLabel(_ row: ConversationListRow) -> some View {
        let unreadCount = unreadCount(row)
        let unread = unreadCount > 0
        let pinned = row.summary.map { ConversationReadState.isPinned($0.conversationID) } ?? false

        return HStack(spacing: DSSpacing.sm) {
            ZStack(alignment: .topTrailing) {
                AvatarBadge(name: row.character.card.name, size: 54)
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
                    Text(row.character.card.name)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Color.dsSceneTextPrimary)
                        .lineLimit(1)

                    if row.character.isMainCharacter {
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
        row.summary.map {
            ConversationReadState.unreadCount(
                conversationID: $0.conversationID,
                assistantMessageDates: $0.assistantMessageDates
            )
        } ?? 0
    }

    private func summaryText(_ summary: ConversationSummaryDTO) -> String {
        switch summary.lastMessageKind {
        case .voice: "[语音]"
        case .quiz: "[小测验]"
        default: summary.lastMessageText.isEmpty ? "打个招呼吧 👋" : summary.lastMessageText
        }
    }

    private func smartTime(_ date: Date) -> String {
        ConversationTimestampFormatter.string(for: date)
    }

    private func reload() async {
        defer { isLoading = false }
        if let loadedProfile = try? await deps.economyStore.profile() {
            currentRegionID = loadedProfile.currentRegionID
        }
        do {
            let friends = try await deps.rosterStore.friends()
            let summaries = try await deps.chatStore.conversationSummaries()
            rows = ConversationListProjection.rows(friends: friends, summaries: summaries)
            updateUnreadCount()
        } catch {
            // 下拉刷新可重试；不以错误页打断导航。
        }
    }

    private func updateUnreadCount() {
        persistedUnreadCount = rows.reduce(into: 0) { total, row in
            guard let summary = row.summary else { return }
            total += ConversationReadState.unreadCount(
                conversationID: summary.conversationID,
                assistantMessageDates: summary.assistantMessageDates
            )
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

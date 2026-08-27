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
            DSSceneBackdrop(imageName: "messages_london_glass", tone: .cool)

            if rows.isEmpty && !isLoading {
                emptyState
            } else {
                List {
                    if visibleRows.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                            .padding(DSSpacing.xl)
                            .dsSceneGlass(tint: Color.white.opacity(0.12))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(visibleRows) { row in
                            NavigationLink {
                                ChatView(character: row.character, deps: deps)
                                    .onAppear {
                                        if let summary = row.summary {
                                            ConversationReadState.markRead(
                                                conversationID: summary.conversationID,
                                                at: summary.lastMessageAt
                                            )
                                        }
                                    }
                                    .onDisappear {
                                        Task { await reload() }
                                    }
                            } label: {
                                rowLabel(row)
                                    .padding(DSSpacing.md)
                                    .dsSceneGlass(
                                        tint: row.summary.map {
                                            ConversationReadState.isPinned($0.conversationID)
                                        } == true
                                            ? Color.dsSky.opacity(0.18)
                                            : Color.white.opacity(0.1),
                                        interactive: true
                                    )
                            }
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
                    .padding(DSSpacing.lg)
                    .dsSceneGlass(radius: DSRadius.card, tint: Color.white.opacity(0.12))
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
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(row.character.card.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
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
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                Text(row.summary.map(summaryText) ?? "打个招呼吧 👋")
                    .font(.subheadline)
                    .foregroundStyle(unread ? .primary : .secondary)
                    .fontWeight(unread ? .semibold : .regular)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, DSSpacing.xs)
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
                Text("完成开场剧情后，你认识的伙伴和消息会出现在这里")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(DSSpacing.xl)
        .frame(maxWidth: 340)
        .dsSceneGlass(tint: Color.white.opacity(0.12))
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
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(date) { return "昨天" }
        if let days = calendar.dateComponents([.day], from: date, to: .now).day, days < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(.dateTime.month().day())
    }

    private func reload() async {
        defer { isLoading = false }
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

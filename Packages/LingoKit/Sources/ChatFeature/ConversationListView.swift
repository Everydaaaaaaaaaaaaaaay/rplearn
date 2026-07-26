import DesignSystem
import PersistenceKit
import SwiftUI

/// QQ 式成熟消息列表：搜索、未读、置顶与滑动操作。
public struct ConversationListView: View {
    private let deps: ChatDependencies

    @State private var rows: [ConversationListRow] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var stateRevision = 0
    @AppStorage("lingotrip.unread.count") private var persistedUnreadCount = 0

    public init(deps: ChatDependencies) {
        self.deps = deps
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
        Group {
            if rows.isEmpty && !isLoading {
                ContentUnavailableView(
                    "还没有会话",
                    systemImage: "bubble.left.and.sparkles",
                    description: Text("完成开场剧情后，你的伙伴会出现在这里")
                )
            } else {
                List {
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
                        }
                        .listRowBackground(
                            row.summary.map { ConversationReadState.isPinned($0.conversationID) } == true
                                ? Color.dsSky.opacity(0.075)
                                : Color.clear
                        )
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            if let conversationID = row.summary?.conversationID {
                                Button {
                                    ConversationReadState.togglePinned(conversationID)
                                    stateRevision += 1
                                } label: {
                                    Label(
                                        ConversationReadState.isPinned(conversationID) ? "取消置顶" : "置顶",
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
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.dsBackground)
            }
        }
        .navigationTitle("消息")
        .searchable(text: $searchText, prompt: "搜索角色")
        .task { await reload() }
        .refreshable { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: ConversationReadState.didChange)) { _ in
            stateRevision += 1
            updateUnreadCount()
        }
        .onChange(of: stateRevision) { updateUnreadCount() }
    }

    private func rowLabel(_ row: ConversationListRow) -> some View {
        let unread = row.summary.map {
            ConversationReadState.isUnread(
                conversationID: $0.conversationID,
                lastMessageAt: $0.lastMessageAt,
                lastMessageRole: $0.lastMessageRole
            )
        } ?? false

        return HStack(spacing: DSSpacing.sm) {
            ZStack(alignment: .topTrailing) {
                AvatarBadge(name: row.character.card.name, size: 48)
                if unread {
                    Circle()
                        .fill(Color.dsDanger)
                        .frame(width: 11, height: 11)
                        .overlay { Circle().stroke(Color.dsSurface, lineWidth: 2) }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: DSSpacing.xs) {
                    Text(row.character.card.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if row.summary.map({ ConversationReadState.isPinned($0.conversationID) }) == true {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.dsSky)
                    }
                    Spacer()
                    if let summary = row.summary {
                        Text(smartTime(summary.lastMessageAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(row.summary.map(summaryText) ?? "打个招呼吧 👋")
                    .font(.subheadline)
                    .foregroundStyle(unread ? .primary : .secondary)
                    .fontWeight(unread ? .medium : .regular)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 5)
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
        persistedUnreadCount = rows.filter {
            guard let summary = $0.summary else { return false }
            return ConversationReadState.isUnread(
                conversationID: summary.conversationID,
                lastMessageAt: summary.lastMessageAt,
                lastMessageRole: summary.lastMessageRole
            )
        }.count
    }
}

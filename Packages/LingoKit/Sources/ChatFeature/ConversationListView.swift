import DesignSystem
import PersistenceKit
import SwiftUI

/// QQ 式成熟消息列表：搜索、未读、置顶与滑动操作。
public struct ConversationListView: View {
    private let deps: ChatDependencies

    @State private var rows: [Row] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var stateRevision = 0
    @AppStorage("lingotrip.unread.count") private var persistedUnreadCount = 0

    struct Row: Identifiable {
        let character: CharacterDTO
        let summary: ConversationSummaryDTO
        var id: UUID { summary.conversationID }
    }

    public init(deps: ChatDependencies) {
        self.deps = deps
    }

    private var visibleRows: [Row] {
        let searched = searchText.isEmpty
            ? rows
            : rows.filter { $0.character.card.name.localizedCaseInsensitiveContains(searchText) }
        return searched.sorted {
            let lhsPinned = ConversationReadState.isPinned($0.summary.conversationID)
            let rhsPinned = ConversationReadState.isPinned($1.summary.conversationID)
            if lhsPinned != rhsPinned { return lhsPinned }
            return $0.summary.lastMessageAt > $1.summary.lastMessageAt
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
                                    ConversationReadState.markRead(
                                        conversationID: row.summary.conversationID,
                                        at: row.summary.lastMessageAt
                                    )
                                }
                        } label: {
                            rowLabel(row)
                        }
                        .listRowBackground(
                            ConversationReadState.isPinned(row.summary.conversationID)
                                ? Color.dsSky.opacity(0.075)
                                : Color.clear
                        )
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                ConversationReadState.togglePinned(row.summary.conversationID)
                                stateRevision += 1
                            } label: {
                                Label(
                                    ConversationReadState.isPinned(row.summary.conversationID) ? "取消置顶" : "置顶",
                                    systemImage: "pin.fill"
                                )
                            }
                            .tint(.dsSky)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                ConversationReadState.markRead(
                                    conversationID: row.summary.conversationID,
                                    at: row.summary.lastMessageAt
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

    private func rowLabel(_ row: Row) -> some View {
        let unread = ConversationReadState.isUnread(
            conversationID: row.summary.conversationID,
            lastMessageAt: row.summary.lastMessageAt,
            lastMessageRole: row.summary.lastMessageRole
        )

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
                    if ConversationReadState.isPinned(row.summary.conversationID) {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.dsSky)
                    }
                    Spacer()
                    Text(smartTime(row.summary.lastMessageAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(summaryText(row.summary))
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
            let friendsByID = Dictionary(uniqueKeysWithValues: friends.map { ($0.id, $0) })
            rows = summaries.compactMap { summary in
                friendsByID[summary.characterID].map { Row(character: $0, summary: summary) }
            }
            updateUnreadCount()
        } catch {
            // 下拉刷新可重试；不以错误页打断导航。
        }
    }

    private func updateUnreadCount() {
        persistedUnreadCount = rows.filter {
            ConversationReadState.isUnread(
                conversationID: $0.summary.conversationID,
                lastMessageAt: $0.summary.lastMessageAt,
                lastMessageRole: $0.summary.lastMessageRole
            )
        }.count
    }
}

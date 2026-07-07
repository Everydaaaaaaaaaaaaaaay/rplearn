import PersistenceKit
import SwiftUI

/// 消息 tab：好友会话列表，进入各角色聊天页。
public struct ConversationListView: View {
    private let deps: ChatDependencies
    @State private var rows: [Row] = []
    @State private var isLoading = true

    struct Row: Identifiable, Equatable {
        var character: CharacterDTO
        var lastMessageText: String?
        var lastMessageAt: Date?

        var id: UUID { character.id }
    }

    public init(deps: ChatDependencies) {
        self.deps = deps
    }

    public var body: some View {
        Group {
            if rows.isEmpty && !isLoading {
                ContentUnavailableView(
                    "还没有朋友",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("完成开场剧情后，你的朋友会出现在这里")
                )
            } else {
                List(rows) { row in
                    NavigationLink {
                        ChatView(character: row.character, deps: deps)
                    } label: {
                        rowLabel(row)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("消息")
        .task {
            await reload()
        }
        .refreshable {
            await reload()
        }
    }

    private func rowLabel(_ row: Row) -> some View {
        HStack(spacing: 12) {
            avatar(row.character)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(row.character.card.name)
                        .font(.headline)
                    Spacer()
                    if let time = row.lastMessageAt {
                        Text(time, style: .time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(row.lastMessageText ?? "打个招呼吧 👋")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    private func avatar(_ character: CharacterDTO) -> some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.15))
            Text(String(character.card.name.prefix(1)))
                .font(.title3.bold())
                .foregroundStyle(Color.accentColor)
        }
        .frame(width: 46, height: 46)
    }

    private func reload() async {
        defer { isLoading = false }
        do {
            let friends = try await deps.rosterStore.friends()
            let summaries = try await deps.chatStore.conversationSummaries()
            let summariesByCharacter = Dictionary(
                uniqueKeysWithValues: summaries.map { ($0.characterID, $0) }
            )
            rows = friends.map { friend in
                let summary = summariesByCharacter[friend.id]
                return Row(
                    character: friend,
                    lastMessageText: summary.flatMap { $0.lastMessageText.isEmpty ? nil : $0.lastMessageText },
                    lastMessageAt: summary?.lastMessageAt
                )
            }
            .sorted { ($0.lastMessageAt ?? .distantPast) > ($1.lastMessageAt ?? .distantPast) }
        } catch {
            // 列表加载失败保持现状即可（下拉可重试）
        }
    }
}

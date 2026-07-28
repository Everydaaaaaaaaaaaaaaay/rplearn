import Foundation
import PersistenceKit

struct ConversationListRow: Identifiable {
    let character: CharacterDTO
    let friendOrder: Int
    let summary: ConversationSummaryDTO?

    /// 导航入口必须跨“尚未开聊 → 创建会话”保持稳定，否则后台列表刷新会让
    /// NavigationLink 的来源行换 ID，并可能把正在展示的聊天页弹回列表。
    var id: UUID { character.id }
}

enum ConversationListProjection {
    static func rows(
        friends: [CharacterDTO],
        summaries: [ConversationSummaryDTO]
    ) -> [ConversationListRow] {
        let friendsByID = Dictionary(uniqueKeysWithValues: friends.map { ($0.id, $0) })
        let orderByID = Dictionary(
            uniqueKeysWithValues: friends.enumerated().map { ($0.element.id, $0.offset) }
        )
        var rows: [ConversationListRow] = summaries.compactMap { summary -> ConversationListRow? in
            guard let character = friendsByID[summary.characterID] else { return nil }
            return ConversationListRow(
                character: character,
                friendOrder: orderByID[character.id] ?? 0,
                summary: summary
            )
        }
        let representedCharacterIDs = Set(rows.map(\.character.id))
        let placeholders: [ConversationListRow] = friends.enumerated().compactMap {
            index, character -> ConversationListRow? in
            guard !representedCharacterIDs.contains(character.id) else { return nil }
            return ConversationListRow(
                character: character,
                friendOrder: index,
                summary: nil
            )
        }
        rows.append(contentsOf: placeholders)
        return rows
    }
}

import Foundation
import PersistenceKit

struct RecentChatRow: Identifiable {
    let character: CharacterDTO
    let summary: ConversationSummaryDTO

    var id: UUID { summary.id }
}

import LLMKit
import PersistenceKit

/// ChatFeature 所需依赖，由组合根注入。
public struct ChatDependencies: Sendable {
    public let chatStore: ChatStore
    public let rosterStore: RosterStore
    public let llm: any LLMClient

    public init(chatStore: ChatStore, rosterStore: RosterStore, llm: any LLMClient) {
        self.chatStore = chatStore
        self.rosterStore = rosterStore
        self.llm = llm
    }
}

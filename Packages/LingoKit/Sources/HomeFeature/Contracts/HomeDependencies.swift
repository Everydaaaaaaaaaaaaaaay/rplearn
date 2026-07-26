import DomainKit
import LLMKit
import PersistenceKit

public struct HomeDependencies: Sendable {
    public let economyStore: EconomyStore
    public let storyProgress: StoryProgressStore
    public let regionCatalog: RegionCatalog
    public let rosterStore: RosterStore
    public let chatStore: ChatStore
    public let llm: any LLMClient

    public init(
        economyStore: EconomyStore,
        storyProgress: StoryProgressStore,
        regionCatalog: RegionCatalog,
        rosterStore: RosterStore,
        chatStore: ChatStore,
        llm: any LLMClient
    ) {
        self.economyStore = economyStore
        self.storyProgress = storyProgress
        self.regionCatalog = regionCatalog
        self.rosterStore = rosterStore
        self.chatStore = chatStore
        self.llm = llm
    }
}

public enum HomeDestination: Hashable, Sendable {
    case stories
    case mainline
    case cityStories
    case activities
}

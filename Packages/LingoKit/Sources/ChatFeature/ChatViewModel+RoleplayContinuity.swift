import DomainKit
import Foundation
import LLMKit
import PersistenceKit

extension ChatViewModel {
    var memoryService: MemoryService {
        MemoryService(
            llm: deps.llm,
            chatStore: deps.chatStore,
            memoryStore: deps.memoryStore,
            economyStore: deps.economyStore
        )
    }

    /// 注入分级记忆、学习者档案与主线引导；文本聊天和实时语音共享同一角色事实来源。
    func makeRoleplayRequest(
        voiceMode: Bool
    ) async -> LLMRequest {
        let memoryService = self.memoryService
        let characterID = character.id
        let itemStore = deps.itemStore
        let economyStore = deps.economyStore
        async let memorySectionsTask = memoryService.memorySections(
            characterID: characterID,
            characterRegionID: character.card.regionID,
            query: messages.last(where: { $0.role == .user })?.text
        )
        async let hasStoryTicketTask = (try? await itemStore.hasTicket(source: .story)) ?? false
        async let profileTask = try? await economyStore.profile()
        async let currentCharacterTask = try? await deps.rosterStore.character(id: characterID)
        async let appointmentContextTask = deps.appointmentContext?(characterID)
        let (memorySections, hasStoryTicket, profile, currentCharacter) = await (
            memorySectionsTask,
            hasStoryTicketTask,
            profileTask,
            currentCharacterTask
        )
        let memoryCutoff = try? await deps.memoryStore.extractionCutoff(characterID: characterID)
        var storySections: [String] = []
        if let storyProgress = deps.storyProgress {
            let sources = StoryExperienceContext.sourceIDs(for: character)
            var records: [StoryProgressDTO] = []
            for source in sources {
                if let record = try? await storyProgress.progress(storyID: source) { records.append(record) }
            }
            storySections = StoryExperienceContext.sections(character: character, progress: records, after: memoryCutoff)
        }
        let subscriptionTier = profile?.subscriptionTier ?? .free
        if let appointmentContext = await appointmentContextTask { storySections.append(appointmentContext) }
        let rawWindow = EconomyService.memoryQuota(for: subscriptionTier).rawWindow
        let mainlineActive = character.isMainCharacter && !hasStoryTicket
        let learner: LearnerContext
        if let profile {
            learner = LearnerContext(profile: profile)
        } else {
            learner = .fallback(difficulty: character.difficultyLevel)
        }
        learnerDifficulty = learner.difficulty
        let request = PromptBuilder.roleplayRequest(
            card: character.card,
            learner: learner,
            history: messages.filter { $0.id != retryingMessageID && (memoryCutoff == nil || $0.createdAt > memoryCutoff!) },
            memorySections: memorySections + storySections,
            relationshipContext: RelationshipEngine.promptContext(
                currentCharacter?.relationship ?? character.relationship
            ),
            growthContext: CharacterGrowthEngine.promptContext(
                currentCharacter?.growth ?? character.growth
            ),
            guidance: mainlineActive ? PromptBuilder.mainlineGuidance : nil,
            voiceMode: voiceMode,
            rawWindow: rawWindow
        )
        return request
    }

    func notifyConversationChanged() {
        NotificationCenter.default.post(
            name: .roleplayConversationDidChange,
            object: character.id
        )
    }
}

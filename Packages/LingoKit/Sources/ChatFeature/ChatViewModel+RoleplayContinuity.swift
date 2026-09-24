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
        quizRequested: Bool,
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
        let (memorySections, hasStoryTicket, profile, currentCharacter) = await (
            memorySectionsTask,
            hasStoryTicketTask,
            profileTask,
            currentCharacterTask
        )
        let subscriptionTier = profile?.subscriptionTier ?? .free
        let rawWindow = EconomyService.memoryQuota(for: subscriptionTier).rawWindow
        let mainlineActive = character.isMainCharacter && !hasStoryTicket
        let baseLearner: LearnerContext
        if let profile {
            baseLearner = LearnerContext(profile: profile)
        } else {
            baseLearner = .fallback(difficulty: character.difficultyLevel)
        }
        let learner = LearnerContext(
            nickname: baseLearner.nickname,
            difficulty: deps.unitLearningDifficulty?(characterID) ?? baseLearner.difficulty,
            goal: baseLearner.goal,
            studyStage: baseLearner.studyStage
        )
        let memoryCutoff = try? await deps.memoryStore.extractionCutoff(characterID: characterID)
        learnerDifficulty = learner.difficulty
        var request = PromptBuilder.roleplayRequest(
            card: character.card,
            learner: learner,
            history: messages.filter { $0.id != retryingMessageID && (memoryCutoff == nil || $0.createdAt > memoryCutoff!) },
            memorySections: memorySections,
            relationshipContext: RelationshipEngine.promptContext(
                currentCharacter?.relationship ?? character.relationship
            ),
            growthContext: CharacterGrowthEngine.promptContext(
                currentCharacter?.growth ?? character.growth
            ),
            guidance: mainlineActive ? PromptBuilder.mainlineGuidance : nil,
            quizRequested: quizRequested,
            voiceMode: voiceMode,
            rawWindow: rawWindow
        )
        if !voiceMode, let instruction = deps.learningInstruction?(characterID) {
            request.system = [request.system, instruction].compactMap { $0 }.joined(separator: "\n\n")
        }
        if let instruction = deps.unitLearningInstruction?(characterID) {
            request.system = [request.system, instruction].compactMap { $0 }.joined(separator: "\n\n")
        }
        return request
    }

    func notifyConversationChanged() {
        NotificationCenter.default.post(
            name: .roleplayConversationDidChange,
            object: character.id
        )
    }
}

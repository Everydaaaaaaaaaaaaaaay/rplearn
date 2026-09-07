import DomainKit
import StoryEngine

/// The server owns reward amounts. Stable reward/event identities also protect
/// users who already completed the retired version of a story.
enum EpisodeCompletion {
    static func settle(resourceName: String, episode: StoryEpisode, deps: StoryDependencies) async throws {
        guard let rewardID = DepartureStoryIdentity.rewardID(for: resourceName) else {
            throw StoryEpisode.ValidationError.invalid("unregistered completion")
        }
        _ = try await deps.progression.completeStory(rewardID)
        if let chapter = MainlineCatalog.chapters.first(where: { $0.storyID == resourceName }),
           ["london", "melbourne", "newyork"].contains(chapter.regionID) {
            try await deps.rosterStore.unlockMainCharacter(regionID: chapter.regionID)
        }
        let participants = RelationshipContextEvent.storyParticipants(
            in: try await deps.rosterStore.allCharacters(),
            speakerNames: Set(episode.nodes.map(\.speaker))
        )
        let events = RelationshipContextEventService(rosterStore: deps.rosterStore)
        for participant in participants {
            _ = try await events.apply(
                characterID: participant.id,
                signal: RelationshipContextEvent.completedStory(characterName: participant.card.name),
                source: .story,
                eventID: RelationshipContextEvent.storyCompletionID(storyID: rewardID, characterID: participant.id)
            )
        }
        try await deps.storyProgress.markCompleted(storyID: resourceName)
    }
}

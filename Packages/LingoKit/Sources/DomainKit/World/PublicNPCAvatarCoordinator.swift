import BackendKit
import Foundation
import PersistenceKit

/// Retries durable local identities and collects server-side portrait bindings without changing the narrative.
public actor PublicNPCAvatarCoordinator {
    private let registry: any PublicNPCRegistry
    private let roster: RosterStore
    private var isSynchronizing = false

    public init(registry: any PublicNPCRegistry, roster: RosterStore) {
        self.registry = registry
        self.roster = roster
    }

    @discardableResult
    public func synchronize() async -> Int {
        guard !isSynchronizing else { return 0 }
        isSynchronizing = true
        defer { isSynchronizing = false }
        guard let characters = try? await roster.allCharacters() else { return 0 }
        var changed = 0
        for character in characters where !character.isMainCharacter && !character.publicIdentityRegistered {
            do {
                try Task.checkCancellation()
                let registered = try await registry.registerPublicNPC(
                    id: character.id,
                    card: PublicNPCAdapter.backendCard(from: character.card)
                )
                try Task.checkCancellation()
                // Read the latest private status; friendship may have changed during the request.
                guard let latest = try await roster.character(id: character.id) else { continue }
                let status: BackendNPCRelationshipStatus = switch latest.contactStatus {
                case .candidate: .candidate
                case .friend: .friend
                case .removed: .removed
                }
                try await registry.linkPublicNPC(npcID: registered.id, localCharacterID: character.id, status: status)
                try Task.checkCancellation()
                // Apply only after linking, so a network failure remains eligible for the next retry.
                try await roster.applyPublicIdentity(
                    characterID: character.id,
                    travelerID: registered.travelerId,
                    card: PublicNPCAdapter.characterCard(from: registered)
                )
                changed += 1
            } catch let error as BackendClientError where error.code == "NPC_AVATAR_COVERAGE_GAP"
                || error.code == "NPC_IDENTITY_CONFLICT"
                || error.code == "NPC_PERSONA_TOO_SIMILAR" {
                // A missing portrait or one conflicted identity must not starve all later characters.
                continue
            } catch {
                // Offline, signed out, cancelled or unavailable: retain the local identity and retry later.
                break
            }
        }
        return changed
    }
}

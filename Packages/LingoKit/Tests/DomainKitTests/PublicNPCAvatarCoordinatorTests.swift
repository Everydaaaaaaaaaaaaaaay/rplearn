import BackendKit
import Foundation
import PersistenceKit
import Testing
@testable import DomainKit

@Suite("Pending NPC portrait synchronization")
struct PublicNPCAvatarCoordinatorTests {
    private actor Registry: PublicNPCRegistry {
        var available = Set<UUID>()
        var registered: [UUID: BackendPublicNPC] = [:]
        var links: [UUID: BackendNPCRelationshipStatus] = [:]
        var requests: [UUID] = []
        var failsLink = false
        var cancelsRequest = false

        func allow(_ ids: [UUID]) { available.formUnion(ids) }
        func failLink(_ value: Bool) { failsLink = value }
        func cancelRequest() { cancelsRequest = true }
        func registerPublicNPC(id: UUID, card: BackendPublicNPCCard) async throws -> BackendPublicNPC {
            requests.append(id)
            if cancelsRequest { throw CancellationError() }
            guard available.contains(id) else {
                throw BackendClientError.api(code: "NPC_AVATAR_COVERAGE_GAP", message: "pending", requestID: nil, status: 409)
            }
            if let existing = registered[id] { return existing }
            var reviewed = PublicNPCAdapter.characterCard(from: BackendPublicNPC(
                avatar: nil, card: card, createdAt: "2026-09-06T00:00:00Z", id: id,
                travelerId: TravelerIDGenerator.make(from: id)
            ))
            reviewed.appearance = "Reviewed angular face and blue coat"
            let result = BackendPublicNPC(
                avatar: .init(id: UUID(), url: URL(string: "https://example.com/\(id).png")!),
                card: PublicNPCAdapter.backendCard(from: reviewed), createdAt: "2026-09-06T00:00:00Z", id: id,
                travelerId: TravelerIDGenerator.make(from: id)
            )
            registered[id] = result
            return result
        }
        func findPublicNPC(travelerID: String) async throws -> BackendPublicNPC { throw BackendClientError.invalidResponse }
        func linkPublicNPC(npcID: UUID, localCharacterID: UUID, status: BackendNPCRelationshipStatus) async throws {
            if failsLink { throw BackendClientError.transport("offline") }
            links[npcID] = status
        }
    }

    private func card(_ name: String) -> CharacterCard {
        CharacterCard(name: name, age: 29, gender: .female, nationality: "British", regionID: "london",
                      occupation: "Radio producer", hobbies: ["Field recording"], appearance: "Provisional",
                      personality: "Curious", background: "Collects neighborhood stories")
    }

    @Test func gapDoesNotStarveLaterCharactersAndSupplementBindsSameIdentity() async throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let roster = RosterStore(modelContainer: container)
        let waiting = try await roster.addCharacter(card: card("Waiting"), difficulty: .junior3, isFriend: false)
        let ready = try await roster.addCharacter(card: card("Ready"), difficulty: .junior3, isFriend: true)
        let registry = Registry()
        await registry.allow([ready])
        let coordinator = PublicNPCAvatarCoordinator(registry: registry, roster: roster)
        #expect(await coordinator.synchronize() == 1)
        #expect(await registry.requests == [waiting, ready])
        #expect(try await roster.character(id: waiting)?.publicIdentityRegistered == false)
        let originalReady = try #require(await roster.character(id: ready))
        #expect(originalReady.card.avatarID != nil)
        #expect(originalReady.contactStatus == .friend)
        #expect(await registry.links[ready] == .friend)
        #expect(originalReady.card.background == card("Ready").background)
        #expect(originalReady.card.personality == card("Ready").personality)
        await registry.allow([waiting])
        // Recreate the coordinator to prove the local store, not in-memory progress, is authoritative.
        let restarted = PublicNPCAvatarCoordinator(registry: registry, roster: roster)
        #expect(await restarted.synchronize() == 1)
        #expect(try await roster.character(id: waiting)?.id == waiting)
        #expect(try await roster.character(id: waiting)?.publicIdentityRegistered == true)
        #expect(try await roster.character(id: ready)?.card.avatarID == originalReady.card.avatarID)
        #expect(await restarted.synchronize() == 0)
        var replacement = originalReady.card
        replacement.avatarID = UUID().uuidString
        do {
            try await roster.applyPublicIdentity(characterID: ready, travelerID: originalReady.travelerID, card: replacement)
            Issue.record("Bound avatar unexpectedly replaced")
        } catch RosterStore.RosterError.identityConflict { }
    }

    @Test func linkFailureRemainsRetryableWithoutLosingPrivateFriendship() async throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let roster = RosterStore(modelContainer: container)
        let id = try await roster.addCharacter(card: card("Offline"), difficulty: .junior3, isFriend: true)
        let registry = Registry()
        await registry.allow([id])
        await registry.failLink(true)
        let coordinator = PublicNPCAvatarCoordinator(registry: registry, roster: roster)
        #expect(await coordinator.synchronize() == 0)
        #expect(try await roster.character(id: id)?.publicIdentityRegistered == false)
        #expect(try await roster.character(id: id)?.contactStatus == .friend)
        await registry.failLink(false)
        #expect(await coordinator.synchronize() == 1)
        #expect(try await roster.character(id: id)?.contactStatus == .friend)
        #expect(await registry.requests == [id, id])
    }

    @Test func cancellationDoesNotApplyTheLateIdentity() async throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let roster = RosterStore(modelContainer: container)
        let id = try await roster.addCharacter(card: card("Cancelled"), difficulty: .junior3, isFriend: false)
        let registry = Registry()
        await registry.allow([id])
        await registry.cancelRequest()
        #expect(await PublicNPCAvatarCoordinator(registry: registry, roster: roster).synchronize() == 0)
        #expect(try await roster.character(id: id)?.publicIdentityRegistered == false)
        #expect(await registry.links.isEmpty)
    }
}

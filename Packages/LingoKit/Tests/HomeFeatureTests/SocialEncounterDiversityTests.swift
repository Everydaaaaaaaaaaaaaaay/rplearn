import BackendKit
import DictKit
import DomainKit
import Foundation
import LLMKit
import PersistenceKit
import SpeechKit
import Testing
@testable import HomeFeature

@Suite("预写相遇，无模型费用", .serialized)
@MainActor
struct SocialEncounterDiversityTests {
    private struct Manifest: Decodable {
        struct Entry: Decodable { let id: UUID; let travelerId: String; let card: BackendPublicNPCCard }
        let entries: [Entry]
    }
    private actor ModelCalls { private(set) var count = 0; func record() { count += 1 } }
    private actor Registry: PublicNPCRegistry {
        let npc: BackendPublicNPC
        var failFirst: Bool
        let empty: Bool
        private(set) var runIDs: [UUID] = []
        init(npc: BackendPublicNPC, failFirst: Bool, empty: Bool) { self.npc = npc; self.failFirst = failFirst; self.empty = empty }
        func selectAuthoredEncounter(context: BackendNPCEncounterContext, libraryVersion: String, runID: UUID) async throws -> BackendPublicNPC? {
            runIDs.append(runID)
            #expect(context.activityId == "park-route")
            if failFirst { failFirst = false; throw BackendClientError.invalidResponse }
            return empty ? nil : npc
        }
        func registerPublicNPC(id: UUID, card: BackendPublicNPCCard) async throws -> BackendPublicNPC { throw BackendClientError.invalidResponse }
        func findPublicNPC(travelerID: String) async throws -> BackendPublicNPC { throw BackendClientError.invalidResponse }
        func linkPublicNPC(npcID: UUID, localCharacterID: UUID, status: BackendNPCRelationshipStatus) async throws {}
    }
    private struct SilentSpeech: SpeechService {
        func speak(_ request: SpeechRequest) async {}
        func stopSpeaking() async {}
    }
    private func settle(_ model: SocialEncounterModel) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while model.busy && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!model.busy)
    }
    @Test("一次抽取、重试身份稳定、本地分支和再次相遇", arguments: [(false, false), (true, false), (false, true)])
    func offlineStory(failFirstPart: Bool, noCandidate: Bool) async throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let economy = EconomyStore(modelContainer: container)
        _ = try await economy.updateProfile {
            $0.currentRegionID = "london"
            $0.difficultyLevel = .junior3
        }
        let calls = ModelCalls()
        let llm = MockLLMProvider(completeHandler: { _ in await calls.record(); throw BackendClientError.invalidResponse })
        let library = try AuthoredEncounterLibrary.bundled()
        let data = try Data(contentsOf: #require(Bundle.main.url(forResource: "npc-library-v3", withExtension: "json")))
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        let source = try #require(manifest.entries.first { $0.card.regionId == "london" && library.entries[$0.id]?.story.actionId == "park-route" })
        let npc = BackendPublicNPC(avatar: nil, card: source.card, createdAt: "2026-09-11T00:00:00Z", id: source.id, travelerId: source.travelerId)
        let registry = Registry(npc: npc, failFirst: failFirstPart, empty: noCandidate)
        let deps = HomeDependencies(
            economyStore: economy,
            itemStore: ItemStore(modelContainer: container),
            ticketStubStore: TicketStubStore(modelContainer: container),
            storyProgress: StoryProgressStore(modelContainer: container),
            regionCatalog: try RegionCatalog(
                url: #require(Bundle.main.url(forResource: "regions", withExtension: "json"))
            ),
            rosterStore: RosterStore(modelContainer: container),
            chatStore: ChatStore(modelContainer: container),
            favorites: FavoritesStore(modelContainer: container),
            dictionary: try DictDatabase(
                databaseURL: #require(Bundle.main.url(forResource: "learner_dictionary", withExtension: "sqlite"))
            ),
            grammarPoints: try GrammarPointStore(
                url: #require(Bundle.main.url(forResource: "grammar_points", withExtension: "json"))
            ),
            speech: SilentSpeech(),
            llm: llm,
            exampleTranslationActions: DictExampleTranslationActions(translate: { _ in nil }),
            npcRegistry: registry
        )
        let region = Region(id:"london", nameEn:"London", nameZh:"伦敦", countryCode:"GB",
            countryNameEn:"United Kingdom", countryNameZh:"英国", taglineZh:"-", landmarks:[], activities:[])
        let activity = try #require(SceneActivity.catalog.first { $0.id == "park-route" })
        let namespace = "authored-test-\(UUID())"
        let model = SocialEncounterModel(activity:activity, region:region, deps:deps, namespace:namespace, encounterRoll:{0}, library:library)
        model.start(); try await settle(model)
        if failFirstPart { #expect(model.error != nil); model.retry(); try await settle(model) }
        #expect(model.error == nil)
        if noCandidate {
            #expect(model.isSolitude)
            #expect(try ActivityEncounterHistory(namespace:namespace,city:region.id).receipts().first?.encountersPerson == false)
            #expect(await calls.count == 0)
            return
        }
        #expect(model.character?.id == npc.id)
        #expect(model.character?.publicIdentityRegistered == true)
        #expect(try await deps.chatStore.recentMessages(characterID:npc.id,limit:100).isEmpty)
        for stage in 0..<3 {
            for _ in 0..<6 where !model.atChoice && !model.atEnding { model.advance(); try await settle(model) }
            if stage < 2 { #expect(model.atChoice); model.choose(stage == 0 ? 1 : 0); try await settle(model) }
            else { model.advance() }
        }
        #expect(model.summary && model.canConnect)
        #expect(model.selections == [1,0])
        let expected = try library.chapter(characterID:npc.id,actionID:activity.id,choices:[1,0])
        #expect(model.chapters.last == expected)
        let messages = try await deps.chatStore.recentMessages(characterID:npc.id,limit:100)
        #expect(messages.count == model.chapters.flatMap(\.beats).filter { $0.speaker == "npc" }.count + 2)
        #expect(await calls.count == 0)
        #expect(Set(await registry.runIDs) == [model.runID])
        let previousCount = await registry.runIDs.count
        model.start(); try await settle(model)
        #expect(await registry.runIDs.count == previousCount)
        let reunion = SocialEncounterModel(activity:activity,region:region,deps:deps,namespace:namespace,encounterRoll:{0},library:library)
        reunion.start(); try await settle(reunion)
        #expect(reunion.alreadyKnown && reunion.chapterCount == 1)
        #expect(reunion.chapters.first == (try library.chapter(characterID:npc.id,actionID:activity.id,choices:[],reunion:true)))
        for _ in 0..<6 where !reunion.atEnding { reunion.advance(); try await settle(reunion) }
        #expect(!reunion.atChoice); reunion.advance(); #expect(reunion.summary)
        #expect(await calls.count == 0)
    }
}

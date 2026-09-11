import BackendKit
import DictKit
import DomainKit
import Foundation
import LLMKit
import PersistenceKit
import SpeechKit
import Testing
@testable import HomeFeature

@Suite("城市偶遇人物多样性闭环", .serialized)
@MainActor
struct SocialEncounterDiversityTests {
    private actor Registry: PublicNPCRegistry {
        private(set) var reviewedNames: [String] = []
        private(set) var registeredNames: [String] = []

        func selectEncounter(context: BackendNPCEncounterContext) async throws -> BackendPublicNPC? { nil }

        func reviewEncounterNPC(
            card: BackendPublicNPCCard,
            diversityProfile: BackendNPCDiversityProfile,
            context: BackendNPCEncounterContext
        ) async throws -> BackendNPCDiversityReview {
            reviewedNames.append(card.name)
            if reviewedNames.count == 1 {
                return BackendNPCDiversityReview(
                    decision: .revise,
                    similarityScore: 91,
                    dimensions: ["occupation-domain", "social-role", "interaction-style"],
                    guidance: ["Choose an occupation outside the service-retail domain."]
                )
            }
            return BackendNPCDiversityReview(decision: .accept, similarityScore: 28, dimensions: [], guidance: [])
        }

        func registerEncounterNPC(
            id: UUID,
            card: BackendPublicNPCCard,
            diversityProfile: BackendNPCDiversityProfile,
            context: BackendNPCEncounterContext
        ) async throws -> BackendPublicNPC {
            registeredNames.append(card.name)
            return BackendPublicNPC(
                avatar: BackendPublicNPC.Avatar(
                    id: UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!,
                    url: URL(string: "https://example.com/reviewed-npc.png")!
                ),
                card: card,
                createdAt: "2026-09-09T00:00:00Z",
                id: id,
                travelerId: "12345678903"
            )
        }

        func registerPublicNPC(id: UUID, card: BackendPublicNPCCard) async throws -> BackendPublicNPC {
            throw BackendClientError.invalidResponse
        }
        func findPublicNPC(travelerID: String) async throws -> BackendPublicNPC {
            throw BackendClientError.invalidResponse
        }
        func linkPublicNPC(
            npcID: UUID,
            localCharacterID: UUID,
            status: BackendNPCRelationshipStatus
        ) async throws {}
    }

    private actor LLMFixture {
        private var generationCount = 0
        private(set) var generationPrompts: [String] = []
        private(set) var planCount = 0

        func complete(_ request: LLMRequest) -> String {
            if case .jsonSchema(let name, _) = request.responseFormat, name == "social_encounter_plan" {
                planCount += 1
                return Self.planJSON
            }
            generationPrompts.append(request.system ?? "")
            generationCount += 1
            return Self.cardJSON(
                name: generationCount == 1 ? "Poppy Hale" : "Dev Singh",
                occupation: generationCount == 1 ? "flower stall seller" : "bicycle mechanic",
                occupationDomain: generationCount == 1 ? "service-retail" : "skilled-trades",
                socialRole: generationCount == 1 ? "creator" : "problem-solver",
                interactionStyle: generationCount == 1 ? "gentle" : "practical",
                motif: generationCount == 1 ? "mastery" : "career-change"
            )
        }

        static var planJSON: String {
            func reply(_ english: String, _ accepts: Bool = false) -> [String: Any] {
                ["english": english, "chinese": "这是一句自然的回应。", "acceptsContact": accepts]
            }
            func choice(_ english: String) -> [String: String] {
                ["english": english, "chinese": "这是一句可选的话。"]
            }
            let branches: [[String: Any]] = (0..<2).map { index in
                ["choice": choice(index == 0 ? "Is this a quiet spot?" : "Do you like this view?"),
                 "reply": reply(index == 0 ? "Yes, it is peaceful." : "The view is lovely."),
                 "endings": [
                    ["intent": "invite", "choice": choice("Would you like to keep in touch?"),
                     "reply": reply(index == 0 ? "Sure, that would be nice." : "Thanks, but I prefer to leave it here.", index == 0)],
                    ["intent": "leave", "choice": choice("Have a nice day!"), "reply": reply("You too. Goodbye!")]
                 ]]
            }
            return String(decoding: try! JSONSerialization.data(withJSONObject: [
                "opening": reply("Hello! Taking a break?"), "branches": branches
            ]), as: UTF8.self)
        }

        private static func cardJSON(
            name: String,
            occupation: String,
            occupationDomain: String,
            socialRole: String,
            interactionStyle: String,
            motif: String
        ) -> String {
            """
            {"name":"\(name)","age":34,"gender":"male","nationality":"British",
            "occupation":"\(occupation)","hobbies":["修理自行车","逛旧货市场"],
            "appearance":"provisional portrait","personality":"practical, candid and calm",
            "speech_style":"short, concrete answers","background":"Changed careers and now repairs useful things.",
            "signature":"Small fixes add up.","birthday":"04-19","hometown":"Bristol","languages":["English"],
            "values":["craft"],"flaws":["occasionally blunt"],
            "conversational_habits":["asks concrete questions"],"boundaries":["respects privacy"],
            "anchor_lines":["Let me think.","That should work."],
            "diversity_profile":{"occupation_domain":"\(occupationDomain)","social_role":"\(socialRole)",
            "interaction_style":"\(interactionStyle)","interest_domains":["technology","sports"],
            "traits":["pragmatic","candid"],"background_motif":"\(motif)",
            "energy":"medium","warmth":"balanced","structure":"structured"},
            "opening_line":"Hi there."}
            """
        }
    }

    private struct SilentSpeech: SpeechService {
        func speak(_ request: SpeechRequest) async {}
        func stopSpeaking() async {}
    }

    @Test("重复候选会带着差异要求重生，通过审查后才落本地并立即带头像")
    func revisesBeforePersistingAndRegistering() async throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let economy = EconomyStore(modelContainer: container)
        _ = try await economy.updateProfile {
            $0.currentRegionID = "london"
            $0.difficultyLevel = .junior3
        }
        let fixture = LLMFixture()
        let llm = MockLLMProvider(completeHandler: { request in await fixture.complete(request) })
        let registry = Registry()
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
        let region = Region(
            id: "london",
            nameEn: "London",
            nameZh: "伦敦",
            countryCode: "GB",
            countryNameEn: "United Kingdom",
            countryNameZh: "英国",
            taglineZh: "-",
            landmarks: [],
            activities: []
        )
        let model = SocialEncounterModel(
            activity: try #require(SceneActivity.catalog.first),
            region: region,
            deps: deps,
            namespace: "social-encounter-diversity-test-\(UUID())",
            encounterRoll: { 0 }
        )
        model.start()
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while model.busy, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(model.busy == false)
        #expect(model.error == nil)
        #expect(model.character?.card.name == "Dev Singh")
        #expect(model.character?.publicIdentityRegistered == true)
        #expect(model.character?.card.avatarRemoteURL == "https://example.com/reviewed-npc.png")
        #expect(model.registrationPending == false)
        #expect(await registry.reviewedNames == ["Poppy Hale", "Dev Singh"])
        #expect(await registry.registeredNames == ["Dev Singh"])
        #expect(try await deps.rosterStore.allCharacters().map(\.card.name) == ["Dev Singh"])
        let prompts = await fixture.generationPrompts
        #expect(prompts.count == 2)
        #expect(prompts[1].contains("outside the service-retail domain"))
        #expect(await fixture.planCount == 1)
        #expect(try await deps.chatStore.recentMessages(characterID: #require(model.character?.id), limit: 20).count == 1)
        // Choosing the second branch must not reuse the first branch's acceptance.
        model.choose(1)
        while model.busy { try await Task.sleep(for: .milliseconds(10)) }
        #expect(model.reply?.english == "The view is lovely.")
        model.advance()
        model.choose(0)
        while model.busy { try await Task.sleep(for: .milliseconds(10)) }
        model.advance()
        #expect(model.error == nil)
        #expect(model.summary)
        #expect(!model.canConnect)
        #expect(await fixture.planCount == 1)
        let messages = try await deps.chatStore.recentMessages(characterID: #require(model.character?.id), limit: 20)
        #expect(messages.count == 5)
        #expect(!messages.contains { $0.text == "Yes, it is peaceful." || $0.text == "Sure, that would be nice." })
        model.start()
        #expect(await fixture.planCount == 1)

    }
}

import BackendKit
import Foundation
import PersistenceKit
import Testing
@testable import SyncKit

@Suite("Backend user state coordinator")
struct BackendUserStateCoordinatorTests {
    private final class MemoryCredentials: AuthCredentialStore, @unchecked Sendable {
        private let credential: StoredAuthCredential

        init(userID: UUID) {
            credential = StoredAuthCredential(
                refreshToken: "refresh",
                refreshTokenExpiresAt: Date(timeIntervalSince1970: 1_893_456_000),
                sessionID: UUID(uuidString: "019c0123-4567-789a-8bcd-ef0123456789")!,
                userID: userID
            )
        }

        func load() throws -> StoredAuthCredential? { credential }
        func remove() throws {}
        func save(_ credential: StoredAuthCredential) throws {}
    }

    private actor StateTransport: BackendTransport {
        private struct OnboardingBody: Decodable {
            let starterRegionId: String
        }

        private struct ProfileBody: Decodable {
            let difficulty: String?
            let displayName: String?
            let hasCompletedProfileSetup: Bool?
            let learningGoal: String?
            let placementCompletedAt: String?
            let placementScore: Int?
            let proficiencySource: String?
            let studyStage: String?
        }

        private var coins = 500
        private var currentRegion = "london"
        private var difficulty = "junior1"
        private var displayName = "旅行者"
        private var hasCompletedOnboarding = false
        private var hasCompletedProfileSetup = false
        private var learningGoal = "dailyConversation"
        private var placementCompletedAt: String?
        private var placementScore: Int?
        private var proficiencySource = "selfReported"
        private var studyStage: String?
        private var starterRegion: String?
        private var firstArrivalTravelID: UUID?
        private var tickets: [UUID] = []
        private var ticketSource = "purchase"
        private var version = 1
        private(set) var mutationHeaders: [String?] = []
        private(set) var snapshotRequestCount = 0

        func data(for request: URLRequest) async throws -> BackendTransportResponse {
            switch (request.httpMethod, request.url?.path) {
            case ("POST", "/v1/auth/refresh"):
                return json(
                    """
                    {
                      "accessToken":"access",
                      "accessTokenExpiresIn":900,
                      "refreshToken":"rotated",
                      "refreshTokenExpiresAt":"2030-01-01T00:00:00.000Z",
                      "sessionId":"019c0123-4567-789a-8bcd-ef0123456789",
                      "tokenType":"Bearer",
                      "userId":"019c0123-4567-789a-8bcd-ef0123456790"
                    }
                    """
                )
            case ("GET", "/v1/sync/snapshot"):
                snapshotRequestCount += 1
                return json(snapshotJSON())
            case ("PATCH", "/v1/me"):
                mutationHeaders.append(request.value(forHTTPHeaderField: "idempotency-key"))
                let body = try JSONDecoder().decode(
                    ProfileBody.self,
                    from: request.httpBody ?? Data()
                )
                difficulty = body.difficulty ?? difficulty
                displayName = body.displayName ?? displayName
                hasCompletedProfileSetup = body.hasCompletedProfileSetup
                    ?? hasCompletedProfileSetup
                learningGoal = body.learningGoal ?? learningGoal
                placementCompletedAt = body.placementCompletedAt ?? placementCompletedAt
                placementScore = body.placementScore ?? placementScore
                proficiencySource = body.proficiencySource ?? proficiencySource
                studyStage = body.studyStage ?? studyStage
                version += 1
                return json(profileJSON())
            case ("POST", "/v1/economy/tickets/purchase"):
                mutationHeaders.append(request.value(forHTTPHeaderField: "idempotency-key"))
                let ticket = UUID(uuidString: "019c0123-4567-789a-8bcd-ef0123456791")!
                tickets = [ticket]
                ticketSource = "purchase"
                coins = 0
                version += 1
                return json(#"{"coins":0,"ticket":\#(ticketJSON(ticket))}"#)
            case ("POST", "/v1/travel"):
                mutationHeaders.append(request.value(forHTTPHeaderField: "idempotency-key"))
                let travelID = UUID(
                    uuidString: "019c0123-4567-789a-8bcd-ef0123456792"
                )!
                firstArrivalTravelID = travelID
                currentRegion = "newyork"
                tickets = []
                version += 1
                return json(
                    """
                    {
                      "consumedTicketId":"019c0123-4567-789a-8bcd-ef0123456791",
                      "fromRegionId":"london",
                      "profileVersion":\(version),
                      "toRegionId":"newyork",
                      "travelId":"\(travelID.uuidString.lowercased())",
                      "traveledAt":"2026-07-26T00:00:00.000Z",
                      "unlockedNow":true
                    }
                    """
                )
            case ("POST", "/v1/progression/starter-ticket"):
                mutationHeaders.append(request.value(forHTTPHeaderField: "idempotency-key"))
                let ticket = UUID(uuidString: "019c0123-4567-789a-8bcd-ef0123456793")!
                tickets = [ticket]
                ticketSource = "quest"
                return json(ticketJSON(ticket, source: "quest"))
            case ("POST", "/v1/progression/onboarding"):
                mutationHeaders.append(request.value(forHTTPHeaderField: "idempotency-key"))
                let body = try JSONDecoder().decode(
                    OnboardingBody.self,
                    from: request.httpBody ?? Data()
                )
                currentRegion = body.starterRegionId
                starterRegion = body.starterRegionId
                hasCompletedOnboarding = true
                version += 1
                return json(profileJSON())
            case ("POST", "/v1/progression/stories/mainline_london/complete"):
                mutationHeaders.append(request.value(forHTTPHeaderField: "idempotency-key"))
                coins += 100
                version += 1
                return json(
                    #"{"coins":\#(coins),"rewardCoins":100,"storyId":"mainline_london"}"#
                )
            default:
                return json(
                    #"{"code":"NOT_FOUND","message":"not found","requestId":"request"}"#,
                    status: 404
                )
            }
        }

        private func snapshotJSON() -> String {
            let ticketValues = tickets
                .map { ticketJSON($0, source: ticketSource) }
                .joined(separator: ",")
            let firstArrivalValues = firstArrivalTravelID.map {
                """
                {
                  "arrivedAt":"2026-07-26T00:00:00.000Z",
                  "fromRegionId":"london",
                  "id":"\($0.uuidString.lowercased())",
                  "toRegionId":"newyork"
                }
                """
            } ?? ""
            return #"{"cursor":"cursor","state":{"firstArrivals":[\#(firstArrivalValues)],"profile":\#(profileJSON()),"tickets":[\#(ticketValues)]}}"#
        }

        private func profileJSON() -> String {
            let starterRegionValue = starterRegion.map { "\"\($0)\"" } ?? "null"
            let placementCompletedAtValue = placementCompletedAt.map { "\"\($0)\"" } ?? "null"
            let placementScoreValue = placementScore.map(String.init) ?? "null"
            let studyStageValue = studyStage.map { "\"\($0)\"" } ?? "null"
            let additionalRegion = currentRegion == "london" ? "" : ",\"\(currentRegion)\""
            return """
            {
              "coins":\(coins),
              "currentRegionId":"\(currentRegion)",
              "difficulty":"\(difficulty)",
              "displayName":"\(displayName)",
              "experiencePoints":0,
              "friendSlotLimit":3,
              "gameLevel":1,
              "hasCompletedOnboarding":\(hasCompletedOnboarding),
              "hasCompletedProfileSetup":\(hasCompletedProfileSetup),
              "learningGoal":"\(learningGoal)",
              "placementCompletedAt":\(placementCompletedAtValue),
              "placementScore":\(placementScoreValue),
              "proficiencySource":"\(proficiencySource)",
              "quizGloballyEnabled":true,
              "starterRegionId":\(starterRegionValue),
              "studyStage":\(studyStageValue),
              "unlockedRegionIds":["london"\(additionalRegion)],
              "updatedAt":"2026-07-26T00:00:00.000Z",
              "version":\(version)
            }
            """
        }

        private func ticketJSON(_ id: UUID, source: String = "purchase") -> String {
            """
            {
              "countryCode":null,
              "createdAt":"2026-07-26T00:00:00.000Z",
              "id":"\(id.uuidString.lowercased())",
              "source":"\(source)",
              "type":"universal"
            }
            """
        }

        private func json(
            _ string: String,
            status: Int = 200
        ) -> BackendTransportResponse {
            BackendTransportResponse(
                data: Data(string.utf8),
                headers: [:],
                statusCode: status
            )
        }
    }

    @Test("server snapshots and commands replace local authority caches")
    func commandAndSnapshotFlow() async throws {
        let userID = UUID(uuidString: "019c0123-4567-789a-8bcd-ef0123456790")!
        let transport = StateTransport()
        let client = BackendClient(
            configuration: BackendConfiguration(baseURL: URL(string: "https://api.example.com")!),
            credentialStore: MemoryCredentials(userID: userID),
            transport: transport
        )
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let accountCache = AccountCacheStore(modelContainer: container)
        let economy = EconomyStore(modelContainer: container)
        let items = ItemStore(modelContainer: container)
        let ticketStubs = TicketStubStore(modelContainer: container)
        let suite = "BackendUserStateCoordinatorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let coordinator = BackendUserStateCoordinator(
            backend: client,
            accountCache: accountCache,
            economyCache: economy,
            itemCache: items,
            ticketStubCache: ticketStubs,
            defaults: defaults
        )

        #expect(try await coordinator.activate(userID: userID) == .synchronized)
        #expect(try await economy.profile().coins == 500)
        #expect(await transport.snapshotRequestCount == 1)
        try await economy.applyAuthoritativeEntitlement(
            tier: .pro,
            friendSlotLimit: 30
        )

        let onboardingProfile = try await coordinator.completeOnboarding(
            starterRegionID: "melbourne"
        )
        #expect(onboardingProfile.hasCompletedOnboarding)
        #expect(onboardingProfile.currentRegionID == "melbourne")
        #expect(try await economy.profile().currentRegionID == "melbourne")
        #expect(await transport.snapshotRequestCount == 1)

        let ticket = try await coordinator.purchaseTicket(
            type: .ticketUniversal,
            countryCode: nil
        )
        #expect(ticket.source == .purchase)
        #expect(try await economy.profile().coins == 0)
        #expect(try await economy.profile().subscriptionTier == .pro)
        #expect(try await economy.profile().friendSlotLimit == 30)
        #expect(try await items.unconsumedTickets().count == 1)

        let travel = try await coordinator.travel(
            targetRegionID: "newyork",
            ticketID: ticket.id
        )
        #expect(travel.unlockedNow)
        #expect(try await economy.profile().currentRegionID == "newyork")
        #expect(try await items.unconsumedTickets().isEmpty)
        #expect(try await ticketStubs.all().map(\.toRegionID) == ["newyork"])

        let updated = try await coordinator.updateProfile {
            $0.hasCompletedOnboarding = true
        }
        #expect(updated.hasCompletedOnboarding)

        #expect(try await coordinator.claimStarterTicket())
        #expect(try await items.unconsumedTickets().first?.source == .quest)
        #expect(try await coordinator.completeStory("mainline_london"))
        #expect(try await economy.profile().coins == 100)
        let headers = await transport.mutationHeaders
        #expect(headers.count == 5)
        #expect(headers.allSatisfy { $0?.isEmpty == false })
    }

    @Test("切换游客空间会隔离账号权威缓存")
    func guestActivationClearsAccountCache() async throws {
        let userID = UUID(uuidString: "019c0123-4567-789a-8bcd-ef0123456790")!
        let client = BackendClient(
            configuration: BackendConfiguration(baseURL: URL(string: "https://api.example.com")!),
            credentialStore: MemoryCredentials(userID: userID),
            transport: StateTransport()
        )
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let economy = EconomyStore(modelContainer: container)
        let suite = "BackendUserStateCoordinatorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let coordinator = BackendUserStateCoordinator(
            backend: client,
            accountCache: AccountCacheStore(modelContainer: container),
            economyCache: economy,
            itemCache: ItemStore(modelContainer: container),
            ticketStubCache: TicketStubStore(modelContainer: container),
            defaults: defaults
        )

        #expect(try await coordinator.activate(userID: userID) == .synchronized)
        #expect(try await economy.profile().coins == 500)

        try await coordinator.activateGuest()

        #expect(try await economy.profile().coins == 0)
        await #expect(throws: BackendClientError.signedOut) {
            try await coordinator.synchronize()
        }
    }

    @Test("首次登录保留游客内容以便后续上传")
    func firstLoginPreservesGuestContent() async throws {
        let userID = UUID(uuidString: "019c0123-4567-789a-8bcd-ef0123456790")!
        let client = BackendClient(
            configuration: BackendConfiguration(baseURL: URL(string: "https://api.example.com")!),
            credentialStore: MemoryCredentials(userID: userID),
            transport: StateTransport()
        )
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let storyProgress = StoryProgressStore(modelContainer: container)
        try await storyProgress.markCompleted(storyID: "guest_story")
        let suite = "BackendUserStateCoordinatorTests.\(UUID().uuidString)"
        let coordinator = BackendUserStateCoordinator(
            backend: client,
            accountCache: AccountCacheStore(modelContainer: container),
            economyCache: EconomyStore(modelContainer: container),
            itemCache: ItemStore(modelContainer: container),
            ticketStubCache: TicketStubStore(modelContainer: container),
            defaults: try #require(UserDefaults(suiteName: suite))
        )

        #expect(try await coordinator.activate(userID: userID) == .synchronized)
        #expect(try await storyProgress.progress(storyID: "guest_story")?.isCompleted == true)
    }

    @Test("首次登录会导入游客学习者资料，且云端已有资料时不会覆盖")
    func firstLoginImportsGuestLearnerProfileOnce() async throws {
        let userID = UUID(uuidString: "019c0123-4567-789a-8bcd-ef0123456790")!
        let transport = StateTransport()
        let client = BackendClient(
            configuration: BackendConfiguration(baseURL: URL(string: "https://api.example.com")!),
            credentialStore: MemoryCredentials(userID: userID),
            transport: transport
        )
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let economy = EconomyStore(modelContainer: container)
        let suite = "BackendUserStateCoordinatorTests.\(UUID().uuidString)"
        let coordinator = BackendUserStateCoordinator(
            backend: client,
            accountCache: AccountCacheStore(modelContainer: container),
            economyCache: economy,
            itemCache: ItemStore(modelContainer: container),
            ticketStubCache: TicketStubStore(modelContainer: container),
            defaults: try #require(UserDefaults(suiteName: suite))
        )
        let placementDate = Date(timeIntervalSince1970: 1_774_972_800)
        let guestProfile = UserProfileDTO(
            displayName: "小咕",
            currentRegionID: "london",
            coins: 0,
            subscriptionTier: .free,
            friendSlotLimit: 10,
            quizGloballyEnabled: true,
            unlockedRegionIDs: [],
            difficultyLevel: .senior2,
            hasCompletedOnboarding: false,
            learningGoal: .studyAbroad,
            studyStage: .seniorHigh,
            proficiencySource: .placement,
            placementScore: 72,
            placementCompletedAt: placementDate,
            hasCompletedProfileSetup: true
        )

        #expect(await coordinator.shouldCaptureGuestProfileForImport())
        #expect(try await coordinator.activate(userID: userID) == .synchronized)
        let imported = try await coordinator.importGuestLearnerProfileIfNeeded(guestProfile)

        #expect(imported.displayName == "小咕")
        #expect(imported.difficultyLevel == .senior2)
        #expect(imported.learningGoal == .studyAbroad)
        #expect(imported.studyStage == .seniorHigh)
        #expect(imported.proficiencySource == .placement)
        #expect(imported.placementScore == 72)
        #expect(imported.placementCompletedAt == placementDate)
        #expect(imported.hasCompletedProfileSetup)
        #expect(!(await coordinator.shouldCaptureGuestProfileForImport()))

        var conflictingGuest = guestProfile
        conflictingGuest.displayName = "不应覆盖"
        let preserved = try await coordinator.importGuestLearnerProfileIfNeeded(conflictingGuest)
        #expect(preserved.displayName == "小咕")
    }
}

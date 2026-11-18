import BackendKit
import DictKit
import DomainKit
import Foundation
import Observation
import LLMKit
import PersistenceKit
import SpeechKit
import Testing
import Synchronization
@testable import HomeFeature

@MainActor
struct CityOutingModelTests {
    @Test func outingProgressDoesNotInvalidateTheApplicationBadge() async throws {
        let source = try makePlaceOutingFixture(), namespace = "place-observation-\(UUID())"
        defer { clean(namespace) }
        let deps = try await dependencies(), gateway = Gateway(saved: source)
        let coordinator = ActivityJourneyCoordinator()
        coordinator.preparePlace(archive: .init(restoring: source),
            region: try #require(deps.regionCatalog.region(id: "london")), deps: deps,
            namespace: namespace, gateway: gateway)
        coordinator.setViewing(true)
        let changes = Mutex(0)
        withObservationTracking {
            _ = coordinator.hasUnreadResult
        } onChange: {
            changes.withLock { $0 += 1 }
        }
        coordinator.start()
        let outing = try #require(coordinator.cityOuting)
        outing.advance()
        try await settle { outing.pendingCount == 0 }
        coordinator.setViewing(true)
        #expect(changes.withLock { $0 } == 0)
        #expect(!coordinator.hasUnreadResult)
        coordinator.reset()
        #expect(changes.withLock { $0 } == 0)
    }

    private actor Gateway: OutingGateway {
        var saved: BackendOuting
        var offline: Bool
        var loseFirstReceipt: Bool
        var receipts: [UUID: BackendOuting] = [:]
        private(set) var operations: [UUID] = []
        init(saved: BackendOuting, offline: Bool = false, loseFirstReceipt: Bool = false) {
            self.saved = saved; self.offline = offline; self.loseFirstReceipt = loseFirstReceipt
        }
        func connect() { offline = false }
        func advanceOnAnotherDevice() throws {
            saved = try PlaceOutingProgress.apply(.init(expectedRevision: saved.revision, type: .read, beatIndex: 0), to: saved)
        }
        func activityCatalog(releaseID: String?) async throws -> BackendActivityCatalog? { nil }
        func activeOuting() async throws -> BackendOuting? { saved }
        func outing(id: UUID) async throws -> BackendOuting { saved }
        func startOuting(id: UUID, releaseID: String, placeID: String) async throws -> BackendOuting {
            guard id == saved.runId else {
                throw BackendClientError.api(code: "OUTING_ALREADY_ACTIVE", message: "Conflict", requestID: nil, status: 409)
            }
            return saved
        }
        func applyOuting(id: UUID, operation: BackendOutingOperation) async throws -> BackendOuting {
            operations.append(operation.operationId)
            if offline { throw BackendClientError.transport("offline") }
            if let receipt = receipts[operation.operationId] { return receipt }
            guard saved.revision == operation.expectedRevision else {
                throw BackendClientError.api(code: "OUTING_CONFLICT", message: "Conflict", requestID: nil, status: 409)
            }
            saved = try PlaceOutingProgress.apply(operation, to: saved)
            receipts[operation.operationId] = saved
            if loseFirstReceipt { loseFirstReceipt = false; throw BackendClientError.transport("receipt lost") }
            return saved
        }
    }
    private struct SilentSpeech: SpeechService {
        func speak(_ request: SpeechRequest) async {}
        func stopSpeaking() async {}
    }
    private func dependencies() async throws -> HomeDependencies {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let economy = EconomyStore(modelContainer: container)
        _ = try await economy.updateProfile { $0.currentRegionID = "london"; $0.difficultyLevel = .junior3 }
        return HomeDependencies(economyStore: economy, itemStore: ItemStore(modelContainer: container),
            ticketStubStore: TicketStubStore(modelContainer: container), storyProgress: StoryProgressStore(modelContainer: container),
            regionCatalog: try RegionCatalog(url: #require(Bundle.main.url(forResource: "regions", withExtension: "json"))),
            rosterStore: RosterStore(modelContainer: container), chatStore: ChatStore(modelContainer: container),
            favorites: FavoritesStore(modelContainer: container),
            dictionary: try DictDatabase(databaseURL: #require(Bundle.main.url(forResource: "learner_dictionary", withExtension: "sqlite"))),
            grammarPoints: try GrammarPointStore(url: #require(Bundle.main.url(forResource: "grammar_points", withExtension: "json"))),
            speech: SilentSpeech(), llm: MockLLMProvider(completeHandler: { _ in throw BackendClientError.invalidResponse }))
    }
    private func settle(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(condition())
    }
    private func clean(_ namespace: String) {
        let prefix = CityOutingArchive.key(namespace: namespace)
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            UserDefaults.standard.removeObject(forKey: key)
        }
        UserDefaults.standard.removeObject(forKey: ActivityJournal(namespace: namespace, city: "london").key)
    }
    private func model(_ archive: CityOutingArchive, deps: HomeDependencies, namespace: String, gateway: Gateway) throws -> CityOutingModel {
        let region = try #require(deps.regionCatalog.region(id: "london"))
        return CityOutingModel(archive: archive, region: region, deps: deps, namespace: namespace, gateway: gateway)
    }

    @Test func draftResumesOtherDevicesOutingAfterStartConflict() async throws {
        let source = try makePlaceOutingFixture(), namespace = "place-concurrent-start-\(UUID())"
        defer { clean(namespace) }
        let deps = try await dependencies(), gateway = Gateway(saved: source)
        try await gateway.advanceOnAnotherDevice()
        let remote = await gateway.saved
        let selectedPlace = BackendActivityPlace(id: "another-place", titleZh: "另一处地点", category: "", photo: source.photo)
        let draft = CityOutingArchive(place: selectedPlace, releaseID: source.releaseId)
        let first = try model(draft, deps: deps, namespace: namespace, gateway: gateway)
        first.start()
        try await settle { !first.busy }

        let cached = try CityOutingArchive.load(namespace: namespace)
        let saved = try #require(cached)
        #expect(saved.needsContinuation)
        #expect(saved.runID == remote.runId)
        #expect(saved.place.id == remote.placeId)
        #expect(saved.snapshot == remote)

        first.retry()
        try await settle { !first.busy }
        first.abandon()
        #expect(try CityOutingArchive.load(namespace: namespace)?.snapshot == remote)
    }

    @Test func retriesALostAcknowledgmentWithTheSameOperationAfterReopening() async throws {
        let source = try makePlaceOutingFixture(), namespace = "place-receipt-\(UUID())"
        defer { clean(namespace) }
        let deps = try await dependencies(), gateway = Gateway(saved: source, loseFirstReceipt: true)
        let first = try model(.init(restoring: source), deps: deps, namespace: namespace, gateway: gateway)
        first.start()
        try await settle { first.synchronizationMessage != nil }
        #expect(first.pendingCount == 1)
        first.pause()
        let cachedValue = try CityOutingArchive.load(namespace: namespace)
        let cached = try #require(cachedValue)
        let operationID = try #require(cached.pending.first?.id)
        let resumed = try model(cached, deps: deps, namespace: namespace, gateway: gateway)
        resumed.start()
        try await settle { resumed.pendingCount == 0 }
        let sent = await gateway.operations
        #expect(sent == [operationID, operationID])
        #expect(resumed.snapshot?.revision == 1)
        let remote = await gateway.saved
        #expect(resumed.snapshot == remote)
        resumed.pause()
    }

    @Test func readsAndChoosesOfflineThenUploadsTheActualPathInOrder() async throws {
        let source = try makePlaceOutingFixture(), namespace = "place-offline-\(UUID())"
        defer { clean(namespace) }
        let deps = try await dependencies(), gateway = Gateway(saved: source, offline: true)
        let first = try model(.init(restoring: source), deps: deps, namespace: namespace, gateway: gateway)
        first.start()
        for stage in 0..<3 {
            while let index = first.snapshot?.beatIndex, index + 1 < first.currentBeats.count { first.advance() }
            first.confirmVisibleOpening()
            if stage < 2 { first.choose(stage == 0 ? 1 : 0) } else { first.advance() }
        }
        #expect(first.snapshot?.status == .completed)
        #expect(first.snapshot?.choices == ["start:1", "b:0"])
        #expect(first.pendingCount > 1)
        first.pause()
        let cachedValue = try CityOutingArchive.load(namespace: namespace)
        let cached = try #require(cachedValue)
        await gateway.connect()
        let resumed = try model(cached, deps: deps, namespace: namespace, gateway: gateway)
        resumed.start()
        try await settle { resumed.pendingCount == 0 }
        let uploaded = await gateway.saved
        #expect(uploaded.status == .completed)
        #expect(uploaded.choices == ["start:1", "b:0"])
        resumed.retry()
        #expect(try ActivityJournal(namespace: namespace, city: "london").records().count == 1)
        resumed.pause()
    }

    @Test func keepsDivergentLocalChoicesWhenRestoringAnotherDevicesProgress() async throws {
        let source = try makePlaceOutingFixture(), namespace = "place-conflict-\(UUID())"
        defer { clean(namespace) }
        let deps = try await dependencies(), gateway = Gateway(saved: source)
        try await gateway.advanceOnAnotherDevice()
        let value = try model(.init(restoring: source), deps: deps, namespace: namespace, gateway: gateway)
        value.start()
        try await settle { value.conflict }
        #expect(value.pendingCount == 1)
        value.restoreServerProgress()
        try await settle { !value.busy && !value.conflict }
        let prefix = CityOutingArchive.key(namespace: namespace) + ".conflict."
        #expect(UserDefaults.standard.dictionaryRepresentation().keys.contains(where: { $0.hasPrefix(prefix) }))
        #expect(value.pendingCount == 0)
        let remote = await gateway.saved
        #expect(value.snapshot == remote)
        value.pause()
    }

    @Test func corruptCacheIsPreservedAndNeverReplacedByAnEmptyArchive() throws {
        let suite = "place-corrupt-\(UUID())", namespace = "fixture"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = Data("broken cache".utf8)
        defaults.set(original, forKey: CityOutingArchive.key(namespace: namespace))
        #expect(throws: (any Error).self) { try CityOutingArchive.load(namespace: namespace, defaults: defaults) }
        #expect(defaults.data(forKey: CityOutingArchive.key(namespace: namespace)) == original)
    }

    @Test func abandoningKeepsOnlyTheTextActuallyReadAndPreservesPhotoEvidence() async throws {
        let source = try makePlaceOutingFixture(), namespace = "place-abandon-\(UUID())"
        defer { clean(namespace) }
        let value = try model(.init(restoring: source), deps: try await dependencies(), namespace: namespace,
                              gateway: Gateway(saved: source, offline: true))
        value.start()
        value.abandon()
        let record = try #require(ActivityJournal(namespace: namespace, city: "london").records().first)
        #expect(record.endedEarly == true)
        #expect(record.photo == source.photo)
        #expect(record.chapters?.first?.beats.count == 1)
        #expect(record.choices.isEmpty)
        value.pause()
    }
}

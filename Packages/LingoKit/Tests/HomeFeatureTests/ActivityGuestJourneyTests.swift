import BackendKit
import DomainKit
import Foundation
import Testing
@testable import HomeFeature

@MainActor
struct ActivityGuestJourneyTests {
    private actor Gateway: OutingGateway {
        var snapshots: [UUID: BackendOuting]
        init(_ snapshots: [BackendOuting]) { self.snapshots = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.runId, $0) }) }
        func activityCatalog(releaseID: String?) async throws -> BackendActivityCatalog? { nil }
        func activeOuting() async throws -> BackendOuting? { snapshots.values.first { ![.completed, .abandoned].contains($0.status) } }
        func outing(id: UUID) async throws -> BackendOuting { try #require(snapshots[id]) }
        func startOuting(id: UUID, releaseID: String, placeID: String) async throws -> BackendOuting { try #require(snapshots[id]) }
        func applyOuting(id: UUID, operation: BackendOutingOperation) async throws -> BackendOuting {
            let current = try #require(snapshots[id])
            let next = try PlaceOutingProgress.apply(operation, to: current)
            snapshots[id] = next
            return next
        }
    }

    @Test func flushesDurableGuestQueueBeforeClaim() async throws {
        let suite = "guest-outing-test-\(UUID())", namespace = "guest"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = try makePlaceOutingFixture()
        let operation = BackendOutingOperation(expectedRevision: 0, type: .read, beatIndex: 0)
        var archive = CityOutingArchive(restoring: original)
        archive.snapshot = try PlaceOutingProgress.apply(operation, to: original)
        archive.pending = [operation]
        try archive.save(namespace: namespace, defaults: defaults)
        let gateway = Gateway([original])
        try await ActivityGuestJourney.prepareForClaim(namespaces: [namespace], gateway: gateway, defaults: defaults)
        let saved = try #require(try CityOutingArchive.load(namespace: namespace, defaults: defaults))
        #expect(saved.pending.isEmpty)
        #expect(saved.snapshot?.revision == 1)
        #expect(saved.snapshot == (try await gateway.outing(id: original.runId)))
    }

    @Test func adoptsServerOnlyAfterPreservingLocalChoicesAndTransfersRecovery() async throws {
        let suite = "guest-conflict-test-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = try makePlaceOutingFixture()
        let operation = BackendOutingOperation(expectedRevision: 0, type: .read, beatIndex: 0)
        var archive = CityOutingArchive(restoring: original)
        archive.snapshot = try PlaceOutingProgress.apply(operation, to: original)
        archive.pending = [operation]
        try archive.save(namespace: "guest", defaults: defaults)
        let localSnapshot = try #require(archive.snapshot)
        let server = try PlaceOutingProgress.apply(.init(expectedRevision: 1, type: .read, beatIndex: 1), to: localSnapshot)
        let gateway = Gateway([server])
        try await ActivityGuestJourney.prepareForClaim(namespaces: ["guest"], gateway: gateway,
                                                        defaults: defaults, adoptServerProgress: true)
        let restored = try #require(try CityOutingArchive.load(namespace: "guest", defaults: defaults))
        #expect(restored.pending.isEmpty)
        #expect(restored.snapshot == server)
        try await ActivityGuestJourney.mergeAfterClaim(from: ["guest"], into: "account", gateway: gateway, defaults: defaults)
        let recoveries = try CityOutingArchive.recoveries(namespace: "account", defaults: defaults)
        #expect(recoveries.contains { $0.snapshot == archive.snapshot && $0.pending.count == 1 })
        #expect(try CityOutingArchive.load(namespace: "account", defaults: defaults)?.snapshot == server)
    }

    @Test func mergesFootprintsAndKeepsRecoverableSourcesAcrossRetries() async throws {
        let suite = "guest-footprints-test-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var guest = try makePlaceOutingFixture(), account = try makePlaceOutingFixture()
        guest.status = .abandoned
        account.status = .abandoned
        try CityOutingArchive(restoring: guest).save(namespace: "guest", defaults: defaults)
        try CityOutingArchive(restoring: account).save(namespace: "account", defaults: defaults)
        _ = try ActivityJournal(namespace: "guest", city: "london", defaults: defaults).endPlaceOuting(guest)
        _ = try ActivityJournal(namespace: "account", city: "london", defaults: defaults).endPlaceOuting(account)
        let gateway = Gateway([guest, account])
        for _ in 0..<2 {
            try await ActivityGuestJourney.mergeAfterClaim(from: ["guest"], into: "account", gateway: gateway, defaults: defaults)
        }
        #expect(try ActivityJournal(namespace: "account", city: "london", defaults: defaults).records().count == 2)
        #expect(try CityOutingArchive.recoveries(namespace: "account", defaults: defaults).count == 2)
        #expect(try CityOutingArchive.load(namespace: "guest", defaults: defaults)?.snapshot == guest)
        #expect(try CityOutingArchive.load(namespace: "account", defaults: defaults) == nil)
    }
}

import BackendKit
import Foundation
import Observation
import PersistenceKit

/// Account-owned display snapshots. Actions still use their authoritative services.
@MainActor @Observable
public final class JourneyPresentationCache {
    public private(set) var profile: UserProfileDTO?
    public private(set) var tickets: [ItemDTO] = []
    public private(set) var stubs: [TicketStubDTO] = []
    public private(set) var completed: Set<String> = []
    public private(set) var mainline: BackendMainlineProgress?
    private var localLoad: Task<Void, Never>?
    private var mainlineLoad: Task<BackendMainlineProgress, Error>?
    private var mainlineUpdatedAt: Date?
    private var catalogs: [String: BackendActivityCatalog] = [:]
    private var catalogLoads: [String: Task<BackendActivityCatalog?, Error>] = [:]

    public init() {}

    public func refreshLocal(economy: EconomyStore, items: ItemStore,
                             progress: StoryProgressStore, ticketStubs: TicketStubStore) async {
        if let localLoad { await localLoad.value; return }
        let task = Task {
            async let newProfile = try? economy.profile()
            async let newTickets = try? items.unconsumedTickets()
            async let newCompleted = try? progress.completedStoryIDs()
            async let newStubs = try? ticketStubs.all()
            if let value = await newProfile { profile = value }
            if let value = await newTickets { tickets = value }
            if let value = await newCompleted { completed = DepartureStoryIdentity.catalogCompletionIDs(value) }
            if let value = await newStubs { stubs = value }
        }
        localLoad = task
        await task.value
        localLoad = nil
    }

    public func refreshMainline(using service: any MainlineServing, force: Bool = false) async throws -> BackendMainlineProgress {
        if let mainlineLoad { return try await mainlineLoad.value }
        if !force, let mainline, let mainlineUpdatedAt, Date().timeIntervalSince(mainlineUpdatedAt) < 15 { return mainline }
        let task = Task { try await service.mainlineProgress() }
        mainlineLoad = task
        defer { mainlineLoad = nil }
        let value = try await task.value
        mainline = value
        mainlineUpdatedAt = .now
        return value
    }

    public func catalog(releaseID: String, cityID: String) -> BackendActivityCatalog? {
        catalogs["\(releaseID)/\(cityID)"]
            ?? CityActivityRelease.bundled().flatMap { $0.releaseId == releaseID ? $0.catalog(in: cityID) : nil }
    }

    public func refreshCatalog(releaseID: String, cityID: String,
                               gateway: any OutingGateway) async throws -> BackendActivityCatalog? {
        let key = "\(releaseID)/\(cityID)"
        if let value = catalogs[key] { return value }
        if let task = catalogLoads[key] { return try await task.value }
        let task = Task { () throws -> BackendActivityCatalog? in
            guard let value = try await gateway.activityCatalog(releaseID: releaseID) else { return nil }
            try CityActivityRelease.validate(value)
            guard value.releaseId == releaseID, value.cityId == cityID else { throw PlaceOutingProgress.ProgressError.invalidContent }
            return value
        }
        catalogLoads[key] = task
        defer { catalogLoads[key] = nil }
        guard let value = try await task.value else { return nil }
        catalogs[key] = value
        return value
    }
}

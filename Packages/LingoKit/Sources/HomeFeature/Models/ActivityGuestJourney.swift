import BackendKit
import DomainKit
import Foundation

/// Replays durable local operations before ownership changes. Source keys stay recoverable.
@MainActor
public enum ActivityGuestJourney {
    public static func prepareForClaim(namespaces: [String], gateway: any OutingGateway,
                                       defaults: UserDefaults = .standard) async throws {
        for namespace in Set(namespaces) {
            guard var archive = try CityOutingArchive.load(namespace: namespace, defaults: defaults),
                  archive.cancelled != true else { continue }
            if archive.snapshot == nil {
                let snapshot = try await gateway.startOuting(id: archive.runID, releaseID: archive.releaseID,
                                                             placeID: archive.place.id)
                try PlaceOutingProgress.validate(snapshot)
                guard snapshot.runId == archive.runID, snapshot.placeId == archive.place.id,
                      snapshot.releaseId == archive.releaseID else { throw PlaceOutingProgress.ProgressError.invalidContent }
                archive.snapshot = snapshot
                try archive.save(namespace: namespace, defaults: defaults)
            }
            while let operation = archive.pending.first {
                let response = try await gateway.applyOuting(id: archive.runID, operation: operation)
                try PlaceOutingProgress.validate(response)
                guard response.runId == archive.runID, response.revision == operation.expectedRevision + 1 else {
                    throw PlaceOutingProgress.ProgressError.staleRevision
                }
                if archive.pending.count == 1, response != archive.snapshot {
                    throw PlaceOutingProgress.ProgressError.staleRevision
                }
                archive.pending.removeFirst()
                try archive.save(namespace: namespace, defaults: defaults)
            }
        }
    }

    public static func mergeAfterClaim(from sources: [String], into destination: String,
                                        gateway: any OutingGateway, defaults: UserDefaults = .standard) async throws {
        for source in Set(sources) where source != destination {
            try ActivityJournal.merge(namespace: source, into: destination, defaults: defaults)
            guard let archive = try CityOutingArchive.load(namespace: source, defaults: defaults) else { continue }
            try archive.preserveRecovery(namespace: destination, defaults: defaults)
            guard archive.snapshot != nil else { continue }
            let current = try await gateway.outing(id: archive.runID)
            try PlaceOutingProgress.validate(current)
            if [.completed, .abandoned].contains(current.status) {
                _ = try ActivityJournal(namespace: destination, city: current.cityId, defaults: defaults)
                    .endPlaceOuting(current)
            }
        }
        if let previous = try CityOutingArchive.load(namespace: destination, defaults: defaults) {
            try previous.preserveRecovery(namespace: destination, defaults: defaults)
            if let snapshot = previous.snapshot {
                let current = try await gateway.outing(id: snapshot.runId)
                if [.completed, .abandoned].contains(current.status) {
                    _ = try ActivityJournal(namespace: destination, city: current.cityId, defaults: defaults)
                        .endPlaceOuting(current)
                }
            }
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var cursor: UUID?
        var visited = Set<UUID>()
        repeat {
            let page = try await gateway.outingHistory(before: cursor)
            for outing in page.outings {
                try PlaceOutingProgress.validate(outing)
                _ = try ActivityJournal(namespace: destination, city: outing.cityId, defaults: defaults)
                    .endPlaceOuting(outing, date: formatter.date(from: outing.createdAt) ?? ISO8601DateFormatter().date(from: outing.createdAt) ?? .now)
            }
            cursor = page.nextCursor
            if let cursor, !visited.insert(cursor).inserted { throw PlaceOutingProgress.ProgressError.invalidContent }
        } while cursor != nil
        if let active = try await gateway.activeOuting() {
            try PlaceOutingProgress.validate(active)
            try CityOutingArchive(restoring: active).save(namespace: destination, defaults: defaults)
        } else {
            // The recoverable copies above precede removal of the single active-session pointer.
            defaults.removeObject(forKey: CityOutingArchive.key(namespace: destination))
        }
    }
}

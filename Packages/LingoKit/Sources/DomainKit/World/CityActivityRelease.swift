import BackendKit
import Foundation
import PersistenceKit

/// Added to the app only after the matching world and its photographs pass release checks.
public struct CityActivityRelease: Decodable, Sendable {
    public let schemaVersion: Int
    public let releaseId: String
    public let manifestHash: String
    public let settingVersion: Int?
    public let characters: [Setting]?

    public struct Setting: Decodable, Sendable {
        public let npc: BackendPublicNPC
        public let migrationExplanationZh: String
    }

    public func migrateContacts(in roster: RosterStore, characterID: UUID? = nil) async throws {
        guard let settingVersion, let characters else { return }
        for setting in characters where characterID == nil || setting.npc.id == characterID {
            try await roster.applyActivitySetting(characterID: setting.npc.id,
                travelerID: setting.npc.travelerId, card: PublicNPCAdapter.characterCard(from: setting.npc),
                releaseID: releaseId, version: settingVersion, explanationZh: setting.migrationExplanationZh)
        }
    }
    public static func bundled() -> Self? { cachedRelease }
    private static let cachedRelease: CityActivityRelease? = {
        guard let url = Bundle.main.url(forResource: "activity-world-release", withExtension: "json"),
              let data = try? Data(contentsOf: url), let release = try? JSONDecoder().decode(Self.self, from: data),
              release.schemaVersion == 1, !release.releaseId.isEmpty, release.manifestHash.count == 64 else { return nil }
        return release
    }()
    public static func validate(_ catalog: BackendActivityCatalog) throws {
        guard (3...5).contains(catalog.places.count),
              Set(catalog.places.map(\.id)).count == catalog.places.count,
              catalog.places.allSatisfy({ $0.photo.cityId == catalog.cityId && $0.photo.placeId == $0.id }) else {
            throw PlaceOutingProgress.ProgressError.invalidContent
        }
    }
}

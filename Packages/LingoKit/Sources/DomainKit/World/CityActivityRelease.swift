import BackendKit
import Foundation

/// Added to the app only after the matching world and its photographs pass release checks.
public struct CityActivityRelease: Decodable, Sendable {
    public let schemaVersion: Int
    public let releaseId: String
    public let manifestHash: String
    public static func bundled() -> Self? {
        guard let url = Bundle.main.url(forResource: "activity-world-release", withExtension: "json"),
              let data = try? Data(contentsOf: url), let release = try? JSONDecoder().decode(Self.self, from: data),
              release.schemaVersion == 1, !release.releaseId.isEmpty, release.manifestHash.count == 64 else { return nil }
        return release
    }
    public static func validate(_ catalog: BackendActivityCatalog) throws {
        guard (3...5).contains(catalog.places.count),
              Set(catalog.places.map(\.id)).count == catalog.places.count,
              catalog.places.allSatisfy({ $0.photo.cityId == catalog.cityId && $0.photo.placeId == $0.id }) else {
            throw PlaceOutingProgress.ProgressError.invalidContent
        }
    }
}

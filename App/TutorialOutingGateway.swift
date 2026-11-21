import BackendKit
import DomainKit
import Foundation

/// Uses the current city's authored preview stories with the regular outing progress rules.
actor TutorialOutingGateway: OutingGateway {
    let catalog: BackendActivityCatalog
    private let templates: [BackendOuting]
    private var sessions: [UUID: BackendOuting] = [:]
    private var receipts: [UUID: BackendOuting] = [:]

    init(cityID: String) throws {
        struct World: Decodable {
            struct Preview: Decodable { let outings: [BackendOuting] }
            let preview: Preview
        }
        guard let catalog = CityActivityRelease.bundled()?.catalog(in: cityID),
              let url = Bundle.main.url(forResource: "activity-world-release", withExtension: "json") else {
            throw BackendClientError.invalidResponse
        }
        self.catalog = catalog
        templates = try JSONDecoder().decode(World.self, from: Data(contentsOf: url)).preview.outings
            .filter { $0.cityId == cityID && $0.releaseId == catalog.releaseId }
    }

    func activityCatalog(releaseID: String?) async throws -> BackendActivityCatalog? {
        guard releaseID == nil || releaseID == catalog.releaseId else { return nil }
        return catalog
    }

    func activeOuting() -> BackendOuting? {
        sessions.values.first { $0.status != .completed && $0.status != .abandoned }
    }

    func outing(id: UUID) async throws -> BackendOuting {
        guard let session = sessions[id] else { throw BackendClientError.invalidResponse }
        return session
    }

    func startOuting(id: UUID, releaseID: String, placeID: String) async throws -> BackendOuting {
        if let session = sessions[id] { return session }
        if activeOuting() != nil {
            throw BackendClientError.api(code: "OUTING_ALREADY_ACTIVE", message: "已有外出进度", requestID: nil, status: 409)
        }
        let matches = templates.filter { $0.placeId == placeID && $0.releaseId == releaseID }
        guard let template = matches.first(where: { $0.mode == .first_meeting }) ?? matches.first,
              var fields = try JSONSerialization.jsonObject(with: JSONEncoder().encode(template)) as? [String: Any] else {
            throw BackendClientError.invalidResponse
        }
        fields["runId"] = id.uuidString
        let session = try JSONDecoder().decode(BackendOuting.self, from: JSONSerialization.data(withJSONObject: fields))
        try PlaceOutingProgress.validate(session)
        sessions[id] = session
        return session
    }

    func applyOuting(id: UUID, operation: BackendOutingOperation) async throws -> BackendOuting {
        if let receipt = receipts[operation.id], receipt.runId == id { return receipt }
        guard let session = sessions[id] else { throw BackendClientError.invalidResponse }
        let updated = try PlaceOutingProgress.apply(operation, to: session)
        sessions[id] = updated
        receipts[operation.id] = updated
        return updated
    }
}

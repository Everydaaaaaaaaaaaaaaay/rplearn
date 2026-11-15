#if DEBUG
import BackendKit
import DomainKit
import Foundation

/// Only injected into the unauthenticated, in-memory preview workspace.
/// Receipts stay in this actor; production routes and accounts are never called.
actor DebugPlaceOutingGateway: OutingGateway {
    static let shared = DebugPlaceOutingGateway()
    static let world = DebugPlaceOutingGateway(allCities: true)
    private let allCities: Bool
    private struct Fixture: Decodable {
        let catalog: BackendActivityCatalog?
        let catalogs: [BackendActivityCatalog]?
        let outings: [BackendOuting]
    }
    private struct State: Codable {
        var sessions: [UUID: BackendOuting] = [:]
        var receipts: [UUID: BackendOuting] = [:]
    }
    private var state: State
    private let storageKey: String
    init(allCities: Bool = false) {
        self.allCities = allCities
        storageKey = (allCities ? "debug.world-outing.gateway.v1." : "debug.place-outing.gateway.v1.") + (ProcessInfo.processInfo.environment["UI_TEST_ACTIVITY_NAMESPACE"] ?? "manual")
        state = UserDefaults.standard.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode(State.self, from: $0) } ?? State()
    }
    private func persist() throws {
        UserDefaults.standard.set(try JSONEncoder().encode(state), forKey: storageKey)
    }
    private func fixture() throws -> Fixture {
        guard let url = Bundle.main.url(forResource: allCities ? "activity-world-release" : "place-outing-preview", withExtension: "json") else {
            throw BackendClientError.invalidResponse
        }
        let data = try Data(contentsOf: url)
        if allCities {
            struct World: Decodable { let preview: Fixture }
            return try JSONDecoder().decode(World.self, from: data).preview
        }
        return try JSONDecoder().decode(Fixture.self, from: data)
    }
    func activityCatalog(releaseID: String?) async throws -> BackendActivityCatalog? {
        let content = try fixture()
        return allCities ? content.catalogs?.first { $0.cityId == (ProcessInfo.processInfo.environment["UI_TEST_SCENE_CITY"] ?? "london") } : content.catalog
    }
    func activeOuting() async throws -> BackendOuting? {
        state.sessions.values.first { ![.completed, .abandoned].contains($0.status) }
    }
    func outing(id: UUID) async throws -> BackendOuting {
        guard let saved = state.sessions[id] else { throw missing }
        return saved
    }
    func startOuting(id: UUID, releaseID: String, placeID: String) async throws -> BackendOuting {
        if let saved = state.sessions[id] { return saved }
        if let active = try await activeOuting(), active.runId != id {
            throw BackendClientError.api(code: "OUTING_ALREADY_ACTIVE", message: "已有外出进度", requestID: nil, status: 409)
        }
        let templates = try fixture().outings.filter { $0.placeId == placeID && $0.releaseId == releaseID }
        let visits = state.sessions.values.filter { $0.placeId == placeID && $0.status != .reserved }
        let known = Set(visits.compactMap { $0.npc?.id })
        let encounters = templates.filter { $0.npc != nil }
        let template: BackendOuting?
        if allCities, visits.count % 7 != 6, !encounters.isEmpty {
            template = encounters.first { $0.npc.map { !known.contains($0.id) } ?? false } ?? encounters[visits.count % encounters.count]
        } else { template = templates.first }
        guard let template,
              var value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(template)) as? [String: Any] else { throw missing }
        if allCities, let npc = template.npc, known.contains(npc.id) { value["mode"] = "reunion" }
        value["runId"] = id.uuidString
        let session = try JSONDecoder().decode(BackendOuting.self, from: JSONSerialization.data(withJSONObject: value))
        try PlaceOutingProgress.validate(session)
        state.sessions[id] = session
        try persist()
        return session
    }
    func applyOuting(id: UUID, operation: BackendOutingOperation) async throws -> BackendOuting {
        if let receipt = state.receipts[operation.id] { return receipt }
        guard let saved = state.sessions[id] else { throw missing }
        let next = try PlaceOutingProgress.apply(operation, to: saved)
        state.sessions[id] = next; state.receipts[operation.id] = next
        try persist()
        return next
    }
    private var missing: BackendClientError {
        .api(code: "OUTING_NOT_FOUND", message: "预览会话已结束，请结束本机预览后重新出发。", requestID: nil, status: 404)
    }
}
#endif

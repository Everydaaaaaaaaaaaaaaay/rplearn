#if DEBUG
import BackendKit
import DomainKit
import Foundation

/// Only injected into the unauthenticated, in-memory preview workspace.
/// Receipts stay in this actor; production routes and accounts are never called.
actor DebugPlaceOutingGateway: OutingGateway {
    static let shared = DebugPlaceOutingGateway()
    private struct Fixture: Decodable {
        let catalog: BackendActivityCatalog
        let outings: [BackendOuting]
    }
    private struct State: Codable {
        var sessions: [UUID: BackendOuting] = [:]
        var receipts: [UUID: BackendOuting] = [:]
    }
    private var state: State
    private let storageKey: String
    init() {
        storageKey = "debug.place-outing.gateway.v1." + (ProcessInfo.processInfo.environment["UI_TEST_ACTIVITY_NAMESPACE"] ?? "manual")
        state = UserDefaults.standard.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode(State.self, from: $0) } ?? State()
    }
    private func persist() throws {
        UserDefaults.standard.set(try JSONEncoder().encode(state), forKey: storageKey)
    }
    private func fixture() throws -> Fixture {
        guard let url = Bundle.main.url(forResource: "place-outing-preview", withExtension: "json") else {
            throw BackendClientError.invalidResponse
        }
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }
    func activityCatalog(releaseID: String?) async throws -> BackendActivityCatalog? { try fixture().catalog }
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
        guard let template = try fixture().outings.first(where: { $0.placeId == placeID && $0.releaseId == releaseID }),
              var value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(template)) as? [String: Any] else { throw missing }
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

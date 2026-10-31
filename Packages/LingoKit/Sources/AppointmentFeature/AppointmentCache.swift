import BackendKit
import CryptoKit
import Foundation

@MainActor
enum AppointmentCaches {
    private static var accounts: [String: AppointmentCache] = [:]

    static func account(_ namespace: String) -> AppointmentCache {
        if let existing = accounts[namespace] { return existing }
        let cache = AppointmentCache(namespace: namespace)
        accounts[namespace] = cache
        return cache
    }
}

struct AppointmentReadingCursor: Codable, Sendable, Hashable {
    var blockID: String
    var beatIndex: Int
}

struct AppointmentReading: Codable, Sendable {
    var cursor: AppointmentReadingCursor?
    var draft = ""
}

struct AppointmentPendingCommand: Codable, Sendable, Hashable {
    let appointmentID: UUID
    let action: BackendAppointmentAction
    let request: BackendAppointmentCommand
}

/// Account-scoped immutable server snapshots, reading state, and a durable command outbox.
/// It never invents story content or applies relationship/memory effects.
actor AppointmentCache {
    private let fileURL: URL
    private var loaded: Snapshot?

    private struct Snapshot: Codable {
        var list: BackendAppointmentList?
        var details: [String: BackendAppointmentDetail] = [:]
        var pending: [String: AppointmentPendingCommand] = [:]
        var reading: [String: AppointmentReading] = [:]
    }

    init(namespace: String, directory: URL? = nil) {
        let root = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Appointments", isDirectory: true)
        let key = SHA256.hash(data: Data(namespace.utf8)).map { String(format: "%02x", $0) }.joined()
        fileURL = root.appendingPathComponent("\(key).json")
    }

    func list() throws -> BackendAppointmentList? { try snapshot().list }
    func detail(_ id: UUID) throws -> BackendAppointmentDetail? { try snapshot().details[id.uuidString] }
    func pending(_ id: UUID) throws -> AppointmentPendingCommand? { try snapshot().pending[id.uuidString] }
    func reading(_ id: UUID) throws -> AppointmentReading { try snapshot().reading[id.uuidString] ?? AppointmentReading() }

    func saveList(_ list: BackendAppointmentList) throws {
        var state = try snapshot(); state.list = list; try persist(state)
    }

    @discardableResult
    func saveDetail(_ detail: BackendAppointmentDetail, acknowledging commandID: UUID? = nil) throws -> BackendAppointmentDetail {
        var state = try snapshot()
        let key = detail.appointment.id.uuidString
        let retained: BackendAppointmentDetail
        if let existing = state.details[key], existing.appointment.revision > detail.appointment.revision {
            retained = existing
        } else { retained = detail }
        state.details[key] = retained
        if let commandID, state.pending[key]?.request.commandId == commandID { state.pending.removeValue(forKey: key) }
        if let index = state.list?.appointments.firstIndex(where: { $0.id == detail.appointment.id }) {
            state.list?.appointments[index] = retained.appointment
        }
        try persist(state)
        return retained
    }

    func savePending(_ pending: AppointmentPendingCommand) throws {
        var state = try snapshot(); state.pending[pending.appointmentID.uuidString] = pending; try persist(state)
    }

    func clearPending(_ id: UUID) throws {
        var state = try snapshot(); state.pending.removeValue(forKey: id.uuidString); try persist(state)
    }

    func saveReading(_ id: UUID, cursor: AppointmentReadingCursor?, draft: String) throws {
        var state = try snapshot(); state.reading[id.uuidString] = AppointmentReading(cursor: cursor, draft: draft); try persist(state)
    }

    private func snapshot() throws -> Snapshot {
        if let loaded { return loaded }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let value = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: fileURL))
            loaded = value; return value
        }
        let value = Snapshot(); loaded = value; return value
    }

    private func persist(_ state: Snapshot) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        loaded = state
    }
}

import Foundation

enum AppointmentRequestTiming {
    static let requestTimeout: TimeInterval = 170
    static let resourceTimeout: TimeInterval = 180

    static func needsGenerationWait(_ path: String) -> Bool {
        let parts = path.split(separator: "/")
        guard parts.count >= 3, parts[0] == "v1", parts[1] == "appointments" else { return false }
        if parts.count == 3 && parts[2] == "detect" { return true }
        guard UUID(uuidString: String(parts[2])) != nil else { return false }
        return parts.count == 3 || (parts.count == 4 && ["start", "choices", "settlement"].contains(String(parts[3])))
    }
}

extension BackendClient: AppointmentServing {
    public func appointments() async throws -> BackendAppointmentList {
        try await get("/v1/appointments")
    }

    public func detectAppointments(characterID: UUID, conversationID: UUID) async throws -> BackendAppointmentList {
        struct Body: Encodable, Sendable { let characterId: UUID; let conversationId: UUID }
        return try await send(path: "/v1/appointments/detect", method: "POST", body: Body(characterId: characterID, conversationId: conversationID))
    }

    public func appointment(_ id: UUID) async throws -> BackendAppointmentDetail {
        try await get("/v1/appointments/\(id.uuidString.lowercased())")
    }

    public func appointmentSettlement(_ id: UUID) async throws -> BackendAppointmentSettlement {
        try await get("/v1/appointments/\(id.uuidString.lowercased())/settlement")
    }

    public func settleAppointment(_ id: UUID, commandID: UUID, expectedCharacterVersion: Int, relationship: BackendJSONValue) async throws -> BackendAppointmentDetail {
        struct Body: Encodable, Sendable {
            let commandId: UUID
            let expectedCharacterVersion: Int
            let relationship: BackendJSONValue
        }
        return try await send(path: "/v1/appointments/\(id.uuidString.lowercased())/settle", method: "POST", body: Body(commandId: commandID, expectedCharacterVersion: expectedCharacterVersion, relationship: relationship), idempotencyKey: commandID)
    }

    public func appointmentCommand(_ id: UUID, action: BackendAppointmentAction, request: BackendAppointmentCommand) async throws -> BackendAppointmentDetail {
        try await send(path: "/v1/appointments/\(id.uuidString.lowercased())/\(action.endpoint)", method: "POST", body: request, idempotencyKey: request.commandId)
    }
}

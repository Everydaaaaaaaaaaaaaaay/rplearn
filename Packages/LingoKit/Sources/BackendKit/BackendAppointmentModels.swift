import Foundation

public struct BackendAppointment: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let characterId: UUID
    public let title: String
    public let cityId: String
    public let cityName: String
    public let timeZone: String
    public let placeName: String
    public let startsAt: String
    public let endsAt: String
    public let windowOpensAt: String
    public let windowClosesAt: String
    public let status: String
    public let revision: Int
}

public struct BackendAppointmentList: Codable, Sendable, Hashable {
    public var appointments: [BackendAppointment]
    public let serverNow: String
    public init(appointments: [BackendAppointment], serverNow: String) {
        self.appointments = appointments; self.serverNow = serverNow
    }
}

public struct BackendAppointmentDetail: Codable, Sendable, Hashable {
    public var appointment: BackendAppointment
    public var session: BackendAppointmentSession?
    public var summary: BackendAppointmentSummary?
    public var serverNow: String
    public init(appointment: BackendAppointment, session: BackendAppointmentSession?, summary: BackendAppointmentSummary?, serverNow: String) {
        self.appointment = appointment; self.session = session; self.summary = summary; self.serverNow = serverNow
    }
}

public struct BackendAppointmentSession: Codable, Sendable, Hashable {
    public let id: UUID
    public var blocks: [BackendAppointmentBlock]
    public var decisions: [BackendAppointmentDecision]
}

public struct BackendAppointmentBlock: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let sequence: Int
    public let location: String
    public let beats: [BackendAppointmentBeat]
    public let choices: [BackendAppointmentChoice]
    public let ending: Bool
}

public struct BackendAppointmentBeat: Codable, Sendable, Hashable {
    public let speaker: String
    public let english: String
    public let chinese: String
}

public struct BackendAppointmentChoice: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let english: String
    public let chinese: String
}

public struct BackendAppointmentDecision: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let blockId: String
    public let input: String
    public let custom: Bool
    public let outcome: String
    public let createdAt: String
}

public struct BackendAppointmentSummary: Codable, Sendable, Hashable {
    public let title: String
    public let reflection: String
    public let affinity: Affinity
    public let memories: [Memory]

    public struct Affinity: Codable, Sendable, Hashable {
        public let status: String
        public let before: Double?
        public let after: Double?
        public let delta: Double?
        public let reason: String
    }

    public struct Memory: Codable, Sendable, Hashable, Identifiable {
        public let id: String
        public let content: String
        public let status: String
    }
}

/// The complete request is persisted before transmission so lost responses reuse the same command.
public struct BackendAppointmentCommand: Codable, Sendable, Hashable {
    public let commandId: UUID
    public let expectedRevision: Int
    public let choiceId: String?
    public let input: String?
    public let finish: Bool?

    public init(commandId: UUID, expectedRevision: Int, choiceId: String? = nil, input: String? = nil, finish: Bool? = nil) {
        self.commandId = commandId; self.expectedRevision = expectedRevision
        self.choiceId = choiceId; self.input = input; self.finish = finish
    }
}

public enum BackendAppointmentAction: String, Codable, Sendable {
    case start, choice, cancel
    public var endpoint: String { self == .choice ? "choices" : rawValue }
}

public protocol AppointmentServing: Sendable {
    func appointments() async throws -> BackendAppointmentList
    func appointment(_ id: UUID) async throws -> BackendAppointmentDetail
    func appointmentCommand(_ id: UUID, action: BackendAppointmentAction, request: BackendAppointmentCommand) async throws -> BackendAppointmentDetail
}

public struct BackendAppointmentSettlement: Codable, Sendable {
    public let eventId: UUID
    public let settlementAt: String
    public let characterVersion: Int
    public let relationship: BackendJSONValue?
    public let review: BackendJSONValue?
    public let settled: Bool
}

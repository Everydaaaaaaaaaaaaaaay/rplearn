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

    public func displayTitle(companionName: String) -> String {
        let name = companionName.replacingOccurrences(of: " · 本地演示", with: "")
        let savedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if savedTitle.hasPrefix("和"), let separator = savedTitle.range(of: "一起") {
            let activity = savedTitle[separator.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !activity.isEmpty { return "和\(name)一起\(activity)" }
        }
        if savedTitle.hasPrefix("和"), savedTitle.hasSuffix("见面") {
            return "和\(name)在\(placeName)见面"
        }
        // Older appointments used literary titles. Use only an activity named in
        // that title, falling back to the agreed place when it gives no activity.
        let activities = [
            ("电影", "看电影"), ("咖啡", "喝咖啡"), ("散步", "散步"),
            ("看展", "看展"), ("野餐", "野餐"), ("晚餐", "吃晚餐"),
            ("午餐", "吃午餐"), ("早餐", "吃早餐"), ("骑行", "骑行"),
            ("逛书店", "逛书店"), ("逛街", "逛街"), ("爬山", "爬山"),
        ]
        if let activity = activities.first(where: { savedTitle.contains($0.0) })?.1 {
            return "和\(name)一起\(activity)"
        }
        return "和\(name)在\(placeName)见面"
    }

    public var displayCityName: String {
        Self.cityDisplayName(id: cityId, fallback: cityName)
    }

    public static func cityDisplayName(id: String, fallback: String) -> String {
        switch id {
        case "london": "London"
        case "newyork": "New York"
        case "capetown": "Cape Town"
        case "singapore": "Singapore"
        case "dublin": "Dublin"
        case "edinburgh": "Edinburgh"
        case "vancouver": "Vancouver"
        case "nairobi": "Nairobi"
        case "sydney": "Sydney"
        case "toronto": "Toronto"
        case "auckland": "Auckland"
        case "melbourne": "Melbourne"
        case "neworleans": "New Orleans"
        case "manchester": "Manchester"
        case "kingston": "Kingston"
        default: fallback
        }
    }
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

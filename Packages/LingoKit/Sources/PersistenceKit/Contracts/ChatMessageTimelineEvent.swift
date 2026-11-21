import Foundation

/// Facts attached to an existing message. They do not participate in the chat protocol as messages.
public struct ChatMessageTimelineEvent: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable {
        case memory, relationship, mood
    }

    public let kind: Kind
    public let state: String
    public let secondary: String?
    public let strength: Int?
    public let delta: Double?

    public init(kind: Kind, state: String, secondary: String? = nil, strength: Int? = nil, delta: Double? = nil) {
        self.kind = kind
        self.state = state
        self.secondary = secondary
        self.strength = strength
        self.delta = delta
    }

    static func decode(_ json: String?) -> [Self] {
        guard let json else { return [] }
        return (try? JSONDecoder().decode([Self].self, from: Data(json.utf8))) ?? []
    }

    static func encode(_ events: [Self]) throws -> String? {
        guard !events.isEmpty else { return nil }
        return String(decoding: try JSONEncoder().encode(events), as: UTF8.self)
    }
}

public extension Notification.Name {
    static let chatTimelineDidChange = Notification.Name("LingoTrip.chatTimelineDidChange")
}

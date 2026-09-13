import Foundation

/// Versioned metadata travels with existing memory content through account sync.
public struct MemoryRecord: Codable, Sendable, Equatable {
    public var key: String
    public var text: String
    public var status: String
    public var evidence: String?
    public var messageID: UUID?
    public var observedAt: Date
    public var eventDate: String?
    public var archived = false
    public var forgotten = false
    public var edited = false

    public init(key: String, text: String, status: String = "active", evidence: String? = nil,
                messageID: UUID? = nil, observedAt: Date = .now, eventDate: String? = nil) {
        self.key = key; self.text = text; self.status = status; self.evidence = evidence
        self.messageID = messageID; self.observedAt = observedAt; self.eventDate = eventDate
    }

    static let prefix = "@lingotrip-memory-v2:"
    static func decode(_ text: String) -> Self? {
        guard text.hasPrefix(prefix), let data = String(text.dropFirst(prefix.count)).data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
    func encoded() throws -> String {
        Self.prefix + String(decoding: try JSONEncoder().encode(self), as: UTF8.self)
    }
}

public extension Notification.Name {
    static let memoryKnowledgeDidChange = Notification.Name("LingoTrip.memoryKnowledgeDidChange")
}

import Foundation

/// Local evidence for replaying a real engine invocation after a content CAS conflict.
/// Never uploaded as a user-controlled social signal or interpreted by PersistenceKit.
public struct RelationshipReplayInput: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case reviewed, contact }
    public let kind: Kind
    public let signalJSON: String?
    public let source: RelationshipEventRecord.Source
    public let messageID: UUID
    public let messageCreatedAt: Date
    public let messageOrderIndex: Int
    public let evaluatedAt: Date
    /// Codable Calendar retains the original identifier and named time zone, including DST rules.
    public let calendar: Calendar

    public init(kind: Kind, signalJSON: String?, source: RelationshipEventRecord.Source,
                messageID: UUID, messageCreatedAt: Date, messageOrderIndex: Int,
                evaluatedAt: Date, calendar: Calendar) {
        self.kind = kind; self.signalJSON = signalJSON; self.source = source
        self.messageID = messageID; self.messageCreatedAt = messageCreatedAt
        self.messageOrderIndex = messageOrderIndex; self.evaluatedAt = evaluatedAt; self.calendar = calendar
    }

    public static func contact(messageID: UUID, messageCreatedAt: Date, messageOrderIndex: Int,
                               at date: Date, calendar: Calendar = .current) -> Self {
        Self(kind: .contact, signalJSON: nil, source: .textChat, messageID: messageID,
             messageCreatedAt: messageCreatedAt, messageOrderIndex: messageOrderIndex,
             evaluatedAt: date, calendar: calendar)
    }

    public static func decodeList(_ json: String?) throws -> [Self] {
        guard let json else { return [] }
        return try JSONDecoder().decode([Self].self, from: Data(json.utf8))
    }
    public static func encodeList(_ inputs: [Self]) throws -> String {
        String(decoding: try JSONEncoder().encode(inputs), as: UTF8.self)
    }
}

public typealias RelationshipReplayClosure = @Sendable ([RelationshipReplayInput], RelationshipSnapshot) throws -> RelationshipSnapshot

public enum ContentRelationshipReconciliation {
    public enum ReconciliationError: Error { case invalidPayload, missingEvidence }

    /// Keep the user's latest intended non-relationship edits; project genuine observations on the remote base.
    public static func reconcile(currentJSON: String, desiredJSON: String, inputs: [RelationshipReplayInput],
                                 evidenceComplete: Bool = true, replay: RelationshipReplayClosure?) throws -> String {
        guard let current = try JSONSerialization.jsonObject(with: Data(currentJSON.utf8)) as? [String: Any],
              var desired = try JSONSerialization.jsonObject(with: Data(desiredJSON.utf8)) as? [String: Any] else {
            throw ReconciliationError.invalidPayload
        }
        let remoteRelationship = try relationship(current["relationship"])
        let desiredRelationship = try relationship(desired["relationship"])
        guard evidenceComplete || remoteRelationship == desiredRelationship else {
            throw ReconciliationError.missingEvidence
        }
        let rebased: RelationshipSnapshot
        if remoteRelationship == desiredRelationship || inputs.isEmpty { rebased = remoteRelationship }
        else {
            guard evidenceComplete, let replay else { throw ReconciliationError.missingEvidence }
            rebased = try replay(inputs, remoteRelationship)
        }
        desired["relationship"] = try JSONSerialization.jsonObject(with: Data(rebased.encodedJSON().utf8))
        return String(decoding: try JSONSerialization.data(withJSONObject: desired, options: .sortedKeys), as: UTF8.self)
    }

    private static func relationship(_ object: Any?) throws -> RelationshipSnapshot {
        guard let object else { return .initial }
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let date = formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text) else {
                throw ReconciliationError.invalidPayload
            }
            return date
        }
        return try decoder.decode(RelationshipSnapshot.self, from: data)
    }
}

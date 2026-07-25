import Foundation
import SwiftData

public enum ContentResourceKind: String, Codable, CaseIterable, Sendable {
    case character
    case conversation
    case favorite
    case memory
    case message
    case quizRecord = "quiz_record"
    case storyProgress = "story_progress"
}

public enum ContentMutationOperation: String, Codable, Sendable {
    case upsert
    case delete
}

@Model
public final class ContentSyncOwnerEntity {
    @Attribute(.unique) public var singletonKey: String
    public var userID: UUID
    public var syncCursor: String?
    public var hasBootstrapped: Bool

    public init(
        userID: UUID,
        syncCursor: String? = nil,
        hasBootstrapped: Bool = false
    ) {
        self.singletonKey = "active"
        self.userID = userID
        self.syncCursor = syncCursor
        self.hasBootstrapped = hasBootstrapped
    }
}

@Model
public final class ContentSyncMetadataEntity {
    @Attribute(.unique) public var metadataKey: String
    public var resourceTypeRaw: String
    public var resourceID: String
    public var localKey: String
    public var version: Int
    public var updatedAt: Date

    public init(
        resourceType: ContentResourceKind,
        resourceID: String,
        localKey: String? = nil,
        version: Int,
        updatedAt: Date = .now
    ) {
        self.metadataKey = "\(resourceType.rawValue):\(resourceID)"
        self.resourceTypeRaw = resourceType.rawValue
        self.resourceID = resourceID
        self.localKey = localKey ?? resourceID
        self.version = version
        self.updatedAt = updatedAt
    }
}

@Model
public final class ContentOutboxEntity {
    @Attribute(.unique) public var commandID: UUID
    public var ownerUserID: UUID
    public var resourceTypeRaw: String
    public var resourceID: String
    public var parentID: String?
    public var operationRaw: String
    public var payloadJSON: String?
    public var expectedVersion: Int
    public var isInFlight: Bool
    public var attemptCount: Int
    public var lastErrorCode: String?
    public var createdAt: Date

    public init(
        commandID: UUID = UUID(),
        ownerUserID: UUID,
        resourceType: ContentResourceKind,
        resourceID: String,
        parentID: String?,
        operation: ContentMutationOperation,
        payloadJSON: String?,
        expectedVersion: Int,
        isInFlight: Bool = false,
        attemptCount: Int = 0,
        lastErrorCode: String? = nil,
        createdAt: Date = .now
    ) {
        self.commandID = commandID
        self.ownerUserID = ownerUserID
        self.resourceTypeRaw = resourceType.rawValue
        self.resourceID = resourceID
        self.parentID = parentID
        self.operationRaw = operation.rawValue
        self.payloadJSON = payloadJSON
        self.expectedVersion = expectedVersion
        self.isInFlight = isInFlight
        self.attemptCount = attemptCount
        self.lastErrorCode = lastErrorCode
        self.createdAt = createdAt
    }
}

public enum SchemaV2: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        SchemaV1.models + [
            ContentSyncOwnerEntity.self,
            ContentSyncMetadataEntity.self,
            ContentOutboxEntity.self,
        ]
    }
}

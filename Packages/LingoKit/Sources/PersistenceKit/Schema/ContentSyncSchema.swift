import Foundation
import SwiftData

public enum ContentResourceKind: String, Codable, CaseIterable, Sendable {
    case character
    case conversation
    case favorite
    case memory
    case message
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

@Model
public final class VoiceMediaLinkEntity {
    @Attribute(.unique) public var messageID: UUID
    public var assetID: UUID?
    public var isRemoteReady: Bool
    public var localFileName: String?
    public var updatedAt: Date

    public init(
        messageID: UUID,
        assetID: UUID? = nil,
        isRemoteReady: Bool = false,
        localFileName: String? = nil,
        updatedAt: Date = .now
    ) {
        self.messageID = messageID
        self.assetID = assetID
        self.isRemoteReady = isRemoteReady
        self.localFileName = localFileName
        self.updatedAt = updatedAt
    }
}

@Model
public final class VoiceMediaUploadEntity {
    @Attribute(.unique) public var assetID: UUID
    public var ownerUserID: UUID
    public var messageID: UUID
    public var localFileName: String
    public var byteSize: Int
    public var checksumSha256: String
    public var contentType: String
    public var attemptCount: Int
    public var nextAttemptAt: Date
    public var lastErrorCode: String?
    public var createdAt: Date

    public init(
        assetID: UUID,
        ownerUserID: UUID,
        messageID: UUID,
        localFileName: String,
        byteSize: Int,
        checksumSha256: String,
        contentType: String,
        attemptCount: Int = 0,
        nextAttemptAt: Date = .now,
        lastErrorCode: String? = nil,
        createdAt: Date = .now
    ) {
        self.assetID = assetID
        self.ownerUserID = ownerUserID
        self.messageID = messageID
        self.localFileName = localFileName
        self.byteSize = byteSize
        self.checksumSha256 = checksumSha256
        self.contentType = contentType
        self.attemptCount = attemptCount
        self.nextAttemptAt = nextAttemptAt
        self.lastErrorCode = lastErrorCode
        self.createdAt = createdAt
    }
}

/// 消息墓碑成功同步后才能执行的远端语音删除任务，避免其他设备先看到悬空引用。
@Model
public final class VoiceMediaDeletionEntity {
    @Attribute(.unique) public var assetID: UUID
    public var ownerUserID: UUID
    public var messageID: UUID
    public var attemptCount: Int
    public var nextAttemptAt: Date
    public var lastErrorCode: String?
    public var createdAt: Date

    public init(
        assetID: UUID,
        ownerUserID: UUID,
        messageID: UUID,
        attemptCount: Int = 0,
        nextAttemptAt: Date = .now,
        lastErrorCode: String? = nil,
        createdAt: Date = .now
    ) {
        self.assetID = assetID
        self.ownerUserID = ownerUserID
        self.messageID = messageID
        self.attemptCount = attemptCount
        self.nextAttemptAt = nextAttemptAt
        self.lastErrorCode = lastErrorCode
        self.createdAt = createdAt
    }
}

/// 当前旅程的路线选择。
@Model
public final class JourneyStateEntity {
    @Attribute(.unique) public var singletonKey: String
    public var starterRegionID: String?

    public init(singletonKey: String = "current", starterRegionID: String? = nil) {
        self.singletonKey = singletonKey
        self.starterRegionID = starterRegionID
    }
}

import Foundation

public struct AuthIdentity: Sendable, Equatable {
    public let sessionID: UUID
    public let userID: UUID

    public init(sessionID: UUID, userID: UUID) {
        self.sessionID = sessionID
        self.userID = userID
    }
}

public struct BackendDevice: Codable, Sendable, Equatable {
    public let appVersion: String?
    public let deviceId: String
    public let deviceName: String?
    public let platform: String

    public init(
        appVersion: String?,
        deviceID: String,
        deviceName: String?,
        platform: String = "ios"
    ) {
        self.appVersion = appVersion
        self.deviceId = deviceID
        self.deviceName = deviceName
        self.platform = platform
    }
}

public struct AppleAuthChallenge: Decodable, Sendable, Equatable {
    public let challengeId: UUID
    public let expiresIn: Int
    public let nonce: String
}

public struct AccountIdentity: Decodable, Identifiable, Sendable, Equatable {
    public let createdAt: String
    public let displayName: String?
    public let email: String?
    public let emailVerified: Bool
    public let id: UUID
    public let provider: String
    public let updatedAt: String
}

struct AccountIdentitiesResponse: Decodable, Sendable {
    let identities: [AccountIdentity]
}

public struct AccountDeviceSession: Decodable, Identifiable, Sendable, Equatable {
    public let appVersion: String?
    public let createdAt: String
    public let current: Bool
    public let deviceId: String
    public let deviceName: String?
    public let id: UUID
    public let lastSeenAt: String
    public let platform: String
}

struct AccountDeviceSessionsResponse: Decodable, Sendable {
    let sessions: [AccountDeviceSession]
}

public struct AccountDeletionReceipt: Decodable, Sendable, Equatable {
    public let cancellationToken: String?
    public let purgeAt: String
    public let requestId: UUID
    public let status: String
}

struct AuthTokenResponse: Decodable, Sendable {
    let accessToken: String
    let accessTokenExpiresIn: Int
    let refreshToken: String
    let refreshTokenExpiresAt: String
    let sessionId: UUID
    let tokenType: String
    let userId: UUID
}

struct AcceptedResponse: Decodable, Sendable {
    let status: String
}

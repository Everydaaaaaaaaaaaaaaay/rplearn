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

import CoreKit
import Foundation

public struct StoredAuthCredential: Codable, Sendable, Equatable {
    public let refreshToken: String
    public let refreshTokenExpiresAt: Date
    public let sessionID: UUID
    public let userID: UUID

    public init(
        refreshToken: String,
        refreshTokenExpiresAt: Date,
        sessionID: UUID,
        userID: UUID
    ) {
        self.refreshToken = refreshToken
        self.refreshTokenExpiresAt = refreshTokenExpiresAt
        self.sessionID = sessionID
        self.userID = userID
    }
}

public protocol AuthCredentialStore: Sendable {
    func load() throws -> StoredAuthCredential?
    func remove() throws
    func save(_ credential: StoredAuthCredential) throws
}

public struct KeychainAuthCredentialStore: AuthCredentialStore {
    private let key = "backend.auth.refresh-credential.v1"
    private let keychain: KeychainStore

    public init(keychain: KeychainStore) {
        self.keychain = keychain
    }

    public func load() throws -> StoredAuthCredential? {
        guard let data = try keychain.data(for: key) else { return nil }
        return try JSONDecoder().decode(StoredAuthCredential.self, from: data)
    }

    public func remove() throws {
        try keychain.removeValue(for: key)
    }

    public func save(_ credential: StoredAuthCredential) throws {
        try keychain.setData(try JSONEncoder().encode(credential), for: key)
    }
}

public struct DeviceIdentifierStore: Sendable {
    private let key = "backend.device.id.v1"
    private let keychain: KeychainStore

    public init(keychain: KeychainStore) {
        self.keychain = keychain
    }

    public func loadOrCreate() throws -> String {
        if let existing = try keychain.string(for: key) {
            return existing
        }
        let created = UUID().uuidString.lowercased()
        try keychain.setString(created, for: key)
        return created
    }
}

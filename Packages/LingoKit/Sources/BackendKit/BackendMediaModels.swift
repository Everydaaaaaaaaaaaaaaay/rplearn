import Foundation

public struct BackendMediaAsset: Decodable, Sendable, Equatable {
    public let byteSize: Int
    public let checksumSha256: String
    public let contentType: String
    public let createdAt: String
    public let deletedAt: String?
    public let id: UUID
    public let pendingExpiresAt: String
    public let purpose: String
    public let readyAt: String?
    public let status: String

    public init(
        byteSize: Int,
        checksumSha256: String,
        contentType: String,
        createdAt: String,
        deletedAt: String?,
        id: UUID,
        pendingExpiresAt: String,
        purpose: String,
        readyAt: String?,
        status: String
    ) {
        self.byteSize = byteSize
        self.checksumSha256 = checksumSha256
        self.contentType = contentType
        self.createdAt = createdAt
        self.deletedAt = deletedAt
        self.id = id
        self.pendingExpiresAt = pendingExpiresAt
        self.purpose = purpose
        self.readyAt = readyAt
        self.status = status
    }
}

public struct BackendMediaTransfer: Decodable, Sendable, Equatable {
    public let expiresAt: String
    public let headers: [String: String]
    public let method: String
    public let url: URL

    public init(
        expiresAt: String,
        headers: [String: String],
        method: String,
        url: URL
    ) {
        self.expiresAt = expiresAt
        self.headers = headers
        self.method = method
        self.url = url
    }
}

public struct BackendMediaReservation: Decodable, Sendable, Equatable {
    public let asset: BackendMediaAsset
    public let upload: BackendMediaTransfer?

    public init(asset: BackendMediaAsset, upload: BackendMediaTransfer?) {
        self.asset = asset
        self.upload = upload
    }
}

public struct BackendMediaDownloadTransfer: Decodable, Sendable, Equatable {
    public let expiresAt: String
    public let url: URL

    public init(expiresAt: String, url: URL) {
        self.expiresAt = expiresAt
        self.url = url
    }
}

public struct BackendMediaDownload: Decodable, Sendable, Equatable {
    public let asset: BackendMediaAsset
    public let download: BackendMediaDownloadTransfer

    public init(
        asset: BackendMediaAsset,
        download: BackendMediaDownloadTransfer
    ) {
        self.asset = asset
        self.download = download
    }
}

private struct BackendMediaReservationBody: Encodable, Sendable {
    let assetId: UUID
    let byteSize: Int
    let checksumSha256: String
    let contentType: String
    let purpose: String
}

private struct BackendMediaEmptyBody: Encodable, Sendable {}

extension BackendClient {
    public func reserveVoiceMedia(
        assetID: UUID,
        byteSize: Int,
        checksumSha256: String,
        contentType: String = "audio/x-caf"
    ) async throws -> BackendMediaReservation {
        try await send(
            path: "/v1/media/assets",
            method: "POST",
            body: BackendMediaReservationBody(
                assetId: assetID,
                byteSize: byteSize,
                checksumSha256: checksumSha256,
                contentType: contentType,
                purpose: "voice_message"
            )
        )
    }

    public func completeVoiceMedia(assetID: UUID) async throws -> BackendMediaAsset {
        try await send(
            path: "/v1/media/assets/\(assetID.uuidString.lowercased())/complete",
            method: "POST",
            body: BackendMediaEmptyBody()
        )
    }

    public func voiceMediaDownload(assetID: UUID) async throws -> BackendMediaDownload {
        try await get(
            "/v1/media/assets/\(assetID.uuidString.lowercased())"
        )
    }

    public func deleteVoiceMedia(assetID: UUID) async throws {
        try await sendWithoutResponse(
            path: "/v1/media/assets/\(assetID.uuidString.lowercased())",
            method: "DELETE",
            body: BackendMediaEmptyBody()
        )
    }
}

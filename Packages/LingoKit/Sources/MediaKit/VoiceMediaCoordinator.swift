import BackendKit
import CoreKit
import CryptoKit
import Foundation
import PersistenceKit
import SpeechKit

public protocol VoiceMediaBackend: Sendable {
    func completeVoiceMedia(assetID: UUID) async throws -> BackendMediaAsset
    func deleteVoiceMedia(assetID: UUID) async throws
    func reserveVoiceMedia(
        assetID: UUID,
        byteSize: Int,
        checksumSha256: String,
        contentType: String
    ) async throws -> BackendMediaReservation
    func voiceMediaDownload(assetID: UUID) async throws -> BackendMediaDownload
}

extension BackendClient: VoiceMediaBackend {}

public protocol VoiceMediaOwnerStore: Sendable {
    func load() -> UUID?
    func save(_ userID: UUID)
}

public final class UserDefaultsVoiceMediaOwnerStore: VoiceMediaOwnerStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String
    private let lock = NSLock()

    public init(
        defaults: UserDefaults = .standard,
        key: String = "voice.media.cached-owner.v1"
    ) {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> UUID? {
        lock.withLock {
            defaults.string(forKey: key).flatMap(UUID.init(uuidString:))
        }
    }

    public func save(_ userID: UUID) {
        lock.withLock {
            defaults.set(userID.uuidString.lowercased(), forKey: key)
        }
    }
}

public actor VoiceMediaCoordinator {
    private let backend: any VoiceMediaBackend
    private let binaryTransport: any VoiceMediaBinaryTransport
    private let chatStore: ChatStore
    private let ownerStore: any VoiceMediaOwnerStore
    private let queueStore: VoiceMediaQueueStore
    private var currentUserID: UUID?
    private var isSynchronizing = false
    private var retryTask: Task<Void, Never>?

    public init(
        backend: any VoiceMediaBackend,
        chatStore: ChatStore,
        queueStore: VoiceMediaQueueStore,
        binaryTransport: any VoiceMediaBinaryTransport = URLSessionVoiceMediaTransport(),
        ownerStore: any VoiceMediaOwnerStore = UserDefaultsVoiceMediaOwnerStore()
    ) {
        self.backend = backend
        self.chatStore = chatStore
        self.queueStore = queueStore
        self.binaryTransport = binaryTransport
        self.ownerStore = ownerStore
    }

    public func activate(userID: UUID) {
        let previous = ownerStore.load()
        if let previous, previous != userID {
            VoiceMessageStorage.removeAccountDirectory(userID: previous)
            VoiceMessageStorage.removeLegacyUnscopedFiles()
        }
        currentUserID = userID
        ownerStore.save(userID)
        scheduleSynchronization()
    }

    public func deactivate() {
        retryTask?.cancel()
        retryTask = nil
        currentUserID = nil
    }

    /// 云端语音备份属于账号增强能力；本地录制、发送与播放不依赖它。
    public var isCloudBackupAvailable: Bool {
        currentUserID != nil
    }

    @discardableResult
    public func enqueue(
        messageID: UUID,
        sourceFileName: String
    ) async throws -> UUID {
        guard let userID = currentUserID else {
            throw BackendClientError.signedOut
        }
        let assetID = UUID()
        let scopedFileName = try VoiceMessageStorage.adopt(
            fileName: sourceFileName,
            userID: userID,
            assetID: assetID
        )
        do {
            let data = try Data(contentsOf: VoiceMessageStorage.url(for: scopedFileName))
            let upload = PendingVoiceMediaUpload(
                assetID: assetID,
                attemptCount: 0,
                byteSize: data.count,
                checksumSha256: Self.checksum(data),
                contentType: "audio/x-caf",
                localFileName: scopedFileName,
                messageID: messageID,
                nextAttemptAt: .now,
                ownerUserID: userID
            )
            try await chatStore.stageVoiceMediaUpload(upload)
            scheduleSynchronization()
            return assetID
        } catch {
            if let scopedURL = try? VoiceMessageStorage.url(for: scopedFileName),
               let sourceURL = try? VoiceMessageStorage.url(for: sourceFileName),
               FileManager.default.fileExists(atPath: scopedURL.path),
               !FileManager.default.fileExists(atPath: sourceURL.path) {
                try? FileManager.default.moveItem(at: scopedURL, to: sourceURL)
            }
            throw error
        }
    }

    public func synchronize() async {
        guard let userID = currentUserID, !isSynchronizing else { return }
        isSynchronizing = true
        retryTask?.cancel()
        retryTask = nil
        defer { isSynchronizing = false }

        while !Task.isCancelled {
            guard currentUserID == userID else { return }
            let upload: PendingVoiceMediaUpload?
            do {
                upload = try await queueStore.next(ownerUserID: userID)
            } catch {
                return
            }
            guard let upload else { break }
            do {
                try await process(upload)
            } catch {
                let delay = min(300, 5 * (1 << min(upload.attemptCount, 6)))
                try? await queueStore.fail(
                    assetID: upload.assetID,
                    errorCode: Self.safeErrorCode(error),
                    retryAt: .now.addingTimeInterval(TimeInterval(delay))
                )
                scheduleRetry(after: delay)
                return
            }
        }

        while !Task.isCancelled {
            guard currentUserID == userID else { return }
            let deletion: PendingVoiceMediaDeletion?
            do {
                deletion = try await queueStore.nextDeletion(ownerUserID: userID)
            } catch {
                return
            }
            guard let deletion else { return }
            do {
                try await backend.deleteVoiceMedia(assetID: deletion.assetID)
                try await queueStore.completeDeletion(assetID: deletion.assetID)
            } catch {
                if Self.isAlreadyDeleted(error) {
                    try? await queueStore.completeDeletion(assetID: deletion.assetID)
                    continue
                }
                let delay = min(300, 5 * (1 << min(deletion.attemptCount, 6)))
                try? await queueStore.failDeletion(
                    assetID: deletion.assetID,
                    errorCode: Self.safeErrorCode(error),
                    retryAt: .now.addingTimeInterval(TimeInterval(delay))
                )
                scheduleRetry(after: delay)
                return
            }
        }
    }

    public func localFile(
        messageID: UUID,
        assetID: UUID?,
        existingFileName: String?
    ) async throws -> String {
        // 游客语音不会上传云端，但录音文件仍在本机；本地命中不能依赖登录态。
        if let existingFileName,
           VoiceMessageStorage.exists(fileName: existingFileName) {
            return existingFileName
        }
        guard let assetID else {
            throw VoiceMediaError.remoteAssetUnavailable
        }
        guard let userID = currentUserID else {
            throw BackendClientError.signedOut
        }

        // 同步记录可能暂时丢失 localFileName；按规范路径再次检查，避免重复下载。
        if let cached = VoiceMessageStorage.existingFileName(
            userID: userID,
            assetID: assetID
        ) {
            try await chatStore.setDownloadedVoiceFileName(
                messageID: messageID,
                assetID: assetID,
                fileName: cached
            )
            return cached
        }

        return try await downloadAndCache(
            messageID: messageID,
            assetID: assetID,
            userID: userID
        )
    }

    private func downloadAndCache(
        messageID: UUID,
        assetID: UUID,
        userID: UUID
    ) async throws -> String {
        for attempt in 0..<2 {
            do {
                guard currentUserID == userID else {
                    throw VoiceMediaError.accountChanged
                }
                // 每次重试都重新申请签名 URL，避免复用过期或失效的下载地址。
                let download = try await backend.voiceMediaDownload(assetID: assetID)
                guard download.asset.id == assetID,
                      download.asset.status == "ready",
                      download.asset.purpose == "voice_message"
                else {
                    throw VoiceMediaError.invalidServerAsset
                }
                let data = try await binaryTransport.download(from: download.download.url)
                guard data.count == download.asset.byteSize,
                      Self.checksum(data) == download.asset.checksumSha256
                else {
                    throw VoiceMediaError.integrityMismatch
                }
                guard currentUserID == userID else {
                    throw VoiceMediaError.accountChanged
                }
                let fileName = try VoiceMessageStorage.store(
                    data,
                    userID: userID,
                    assetID: assetID
                )
                try await chatStore.setDownloadedVoiceFileName(
                    messageID: messageID,
                    assetID: assetID,
                    fileName: fileName
                )
                return fileName
            } catch {
                guard attempt == 0, Self.shouldRetryDownload(error) else {
                    throw error
                }
            }
        }
        throw VoiceMediaError.remoteAssetUnavailable
    }

    private func process(_ upload: PendingVoiceMediaUpload) async throws {
        guard currentUserID == upload.ownerUserID else {
            throw VoiceMediaError.accountChanged
        }
        let fileURL = try VoiceMessageStorage.url(for: upload.localFileName)
        let data = try Data(contentsOf: fileURL)
        guard data.count == upload.byteSize,
              Self.checksum(data) == upload.checksumSha256
        else {
            throw VoiceMediaError.localFileChanged
        }
        let reservation = try await backend.reserveVoiceMedia(
            assetID: upload.assetID,
            byteSize: upload.byteSize,
            checksumSha256: upload.checksumSha256,
            contentType: upload.contentType
        )
        guard reservation.asset.id == upload.assetID else {
            throw VoiceMediaError.invalidServerAsset
        }
        if let transfer = reservation.upload {
            try await binaryTransport.upload(
                data,
                to: transfer.url,
                method: transfer.method,
                headers: transfer.headers
            )
        }
        let completed = try await backend.completeVoiceMedia(assetID: upload.assetID)
        guard completed.id == upload.assetID, completed.status == "ready" else {
            throw VoiceMediaError.invalidServerAsset
        }
        guard currentUserID == upload.ownerUserID else {
            throw VoiceMediaError.accountChanged
        }
        let attached = try await chatStore.markVoiceMediaReady(
            messageID: upload.messageID,
            assetID: upload.assetID
        )
        if !attached {
            try await backend.deleteVoiceMedia(assetID: upload.assetID)
        }
        try await queueStore.complete(assetID: upload.assetID)
    }

    private func scheduleSynchronization() {
        Task(priority: .utility) { [weak self] in
            await self?.synchronize()
        }
    }

    private func scheduleRetry(after seconds: Int) {
        retryTask?.cancel()
        retryTask = Task(priority: .utility) { [weak self] in
            try? await Task.sleep(for: .seconds(Int64(seconds)))
            guard !Task.isCancelled else { return }
            await self?.synchronize()
        }
    }

    private static func checksum(_ data: Data) -> String {
        Data(SHA256.hash(data: data)).base64EncodedString()
    }

    private static func safeErrorCode(_ error: Error) -> String {
        if let backend = error as? BackendClientError {
            switch backend {
            case .api(let code, _, _, _): return code
            case .invalidResponse: return "INVALID_RESPONSE"
            case .signedOut: return "SIGNED_OUT"
            case .transport: return "TRANSPORT_ERROR"
            }
        }
        return String(describing: type(of: error))
    }

    private static func shouldRetryDownload(_ error: Error) -> Bool {
        if let voiceMedia = error as? VoiceMediaError {
            return voiceMedia == .integrityMismatch
        }
        if let backend = error as? BackendClientError {
            return switch backend {
            case .transport, .invalidResponse:
                true
            case .api(_, _, _, let status):
                status == 408 || status == 429 || status >= 500
            case .signedOut:
                false
            }
        }
        if let transport = error as? VoiceMediaTransportError {
            return switch transport {
            case .invalidResponse:
                true
            case .httpStatus(let status):
                status == 401 || status == 403 || status == 408
                    || status == 429 || status >= 500
            }
        }
        return error is URLError
    }

    private static func isAlreadyDeleted(_ error: Error) -> Bool {
        guard let backend = error as? BackendClientError else { return false }
        if case .api(_, _, _, let status) = backend {
            return status == 404 || status == 410
        }
        return false
    }
}

public enum VoiceMediaError: Error, Sendable, Equatable {
    case accountChanged
    case integrityMismatch
    case invalidServerAsset
    case localFileChanged
    case remoteAssetUnavailable
}

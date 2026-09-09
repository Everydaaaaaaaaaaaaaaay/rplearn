import Foundation

public struct AccountStorePreparation: Sendable, Equatable {
    public let importedLegacyStore: Bool
    public let storeURL: URL

    public init(importedLegacyStore: Bool, storeURL: URL) {
        self.importedLegacyStore = importedLegacyStore
        self.storeURL = storeURL
    }
}

/// Stable, non-secret account partition for SwiftData files.
///
/// The UUID is already the server's opaque account identifier. Keeping every account in its
/// own directory makes switching atomic at the composition root and lets verified accounts keep
/// independent offline caches on the same device.
public enum AccountStoreLocation {
    public static func storeURL(
        for userID: UUID,
        applicationSupportDirectory: URL = .applicationSupportDirectory
    ) -> URL {
        applicationSupportDirectory
            .appending(path: "LingoTrip", directoryHint: .isDirectory)
            .appending(path: "Accounts", directoryHint: .isDirectory)
            .appending(
                path: userID.uuidString.lowercased(),
                directoryHint: .isDirectory
            )
            .appending(path: "LingoTrip.store", directoryHint: .notDirectory)
    }

    public static func hasStore(
        for userID: UUID,
        applicationSupportDirectory: URL = .applicationSupportDirectory,
        fileManager: FileManager = .default
    ) -> Bool {
        fileManager.fileExists(
            atPath: storeURL(
                for: userID,
                applicationSupportDirectory: applicationSupportDirectory
            ).path
        )
    }

    /// Copies the pre-account-partition `default.store` only when its recorded owner is the
    /// account being opened, or when it is an unclaimed legacy guest journey. The source is never
    /// moved or deleted, so a failed import remains recoverable.
    @discardableResult
    public static func prepare(
        for userID: UUID,
        legacyOwnerID: UUID?,
        legacyWasGuest: Bool,
        applicationSupportDirectory: URL = .applicationSupportDirectory,
        fileManager: FileManager = .default
    ) throws -> AccountStorePreparation {
        let destination = storeURL(
            for: userID,
            applicationSupportDirectory: applicationSupportDirectory
        )
        if fileManager.fileExists(atPath: destination.path) {
            return AccountStorePreparation(
                importedLegacyStore: false,
                storeURL: destination
            )
        }

        let directory = destination.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )

        let legacy = applicationSupportDirectory.appending(path: "default.store")
        let ownsLegacyStore = legacyOwnerID == userID
            || legacyWasGuest
            || legacyOwnerID == nil
        guard ownsLegacyStore, fileManager.fileExists(atPath: legacy.path) else {
            return AccountStorePreparation(
                importedLegacyStore: false,
                storeURL: destination
            )
        }

        let staging = directory.appending(
            path: ".legacy-import-v1",
            directoryHint: .isDirectory
        )
        if fileManager.fileExists(atPath: staging.path) {
            try fileManager.removeItem(at: staging)
        }
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)

        let suffixes = ["", "-wal", "-shm"]
        do {
            for suffix in suffixes {
                let source = URL(filePath: legacy.path + suffix)
                guard fileManager.fileExists(atPath: source.path) else { continue }
                try fileManager.copyItem(
                    at: source,
                    to: staging.appending(path: "LingoTrip.store" + suffix)
                )
            }

            // Publish SQLite companions first and the main store last. Until the final move the
            // destination cannot be mistaken for a complete account database after interruption.
            for suffix in ["-wal", "-shm", ""] {
                let staged = staging.appending(path: "LingoTrip.store" + suffix)
                guard fileManager.fileExists(atPath: staged.path) else { continue }
                let target = URL(filePath: destination.path + suffix)
                if fileManager.fileExists(atPath: target.path) {
                    try fileManager.removeItem(at: target)
                }
                try fileManager.moveItem(at: staged, to: target)
            }
            try fileManager.removeItem(at: staging)
            return AccountStorePreparation(
                importedLegacyStore: true,
                storeURL: destination
            )
        } catch {
            // Only incomplete destination copies are cleaned. The legacy source remains intact.
            for suffix in suffixes {
                let target = URL(filePath: destination.path + suffix)
                if fileManager.fileExists(atPath: target.path) {
                    try? fileManager.removeItem(at: target)
                }
            }
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }
}

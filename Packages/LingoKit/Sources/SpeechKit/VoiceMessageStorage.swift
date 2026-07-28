import Foundation

/// 语音文件存储：新文件按账号放在 VoiceMessages/{userID}/{assetID}.caf。
public enum VoiceMessageStorage {
    public enum StorageError: Error {
        case invalidFileName
        case destinationExists
    }

    public static func directory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent("VoiceMessages", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true,
                attributes: [
                    .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
                ]
            )
        }
        return dir
    }

    public static func newFileName() -> String {
        "\(UUID().uuidString).caf"
    }

    public static func url(for fileName: String) throws -> URL {
        let components = fileName.split(separator: "/", omittingEmptySubsequences: false)
        guard (components.count == 1 || components.count == 2),
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              fileName.hasSuffix(".caf"),
              !fileName.hasPrefix("/")
        else {
            throw StorageError.invalidFileName
        }
        if components.count == 2,
           UUID(uuidString: String(components[0])) == nil {
            throw StorageError.invalidFileName
        }
        let stem = String(components.last!.dropLast(4))
        guard UUID(uuidString: stem) != nil else {
            throw StorageError.invalidFileName
        }
        return try components.reduce(directory()) {
            $0.appendingPathComponent(String($1))
        }
    }

    public static func adopt(
        fileName: String,
        userID: UUID,
        assetID: UUID
    ) throws -> String {
        let scoped = scopedFileName(userID: userID, assetID: assetID)
        let source = try url(for: fileName)
        let destination = try url(for: scoped)
        guard source != destination else { return scoped }
        let parent = destination.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parent.path) {
            try FileManager.default.createDirectory(
                at: parent,
                withIntermediateDirectories: true,
                attributes: [
                    .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
                ]
            )
        }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw StorageError.destinationExists
        }
        try FileManager.default.moveItem(at: source, to: destination)
        return scoped
    }

    public static func store(
        _ data: Data,
        userID: UUID,
        assetID: UUID
    ) throws -> String {
        let fileName = scopedFileName(userID: userID, assetID: assetID)
        let destination = try url(for: fileName)
        let parent = destination.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parent.path) {
            try FileManager.default.createDirectory(
                at: parent,
                withIntermediateDirectories: true,
                attributes: [
                    .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
                ]
            )
        }
        try data.write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return fileName
    }

    public static func exists(fileName: String) -> Bool {
        guard let url = try? url(for: fileName) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// 返回账号与远端资产对应的本地缓存文件；文件不存在时返回 nil。
    public static func existingFileName(userID: UUID, assetID: UUID) -> String? {
        let fileName = scopedFileName(userID: userID, assetID: assetID)
        return exists(fileName: fileName) ? fileName : nil
    }

    public static func removeAccountDirectory(userID: UUID) {
        guard let root = try? directory() else { return }
        let account = root.appendingPathComponent(
            userID.uuidString.lowercased(),
            isDirectory: true
        )
        try? FileManager.default.removeItem(at: account)
    }

    public static func removeLegacyUnscopedFiles() {
        guard let root = try? directory(),
              let contents = try? FileManager.default.contentsOfDirectory(
                  at: root,
                  includingPropertiesForKeys: [.isRegularFileKey]
              )
        else { return }
        for url in contents where url.pathExtension == "caf" {
            try? FileManager.default.removeItem(at: url)
        }
    }

    public static func delete(fileName: String) {
        guard let url = try? url(for: fileName) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func scopedFileName(userID: UUID, assetID: UUID) -> String {
        "\(userID.uuidString.lowercased())/\(assetID.uuidString.lowercased()).caf"
    }
}

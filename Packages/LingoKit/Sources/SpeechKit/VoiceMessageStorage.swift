import Foundation

/// 语音文件存储：Application Support/VoiceMessages/{uuid}.caf，DB 只存文件名（plan.md §2）。
public enum VoiceMessageStorage {
    public static func directory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent("VoiceMessages", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    public static func newFileName() -> String {
        "\(UUID().uuidString).caf"
    }

    public static func url(for fileName: String) throws -> URL {
        try directory().appendingPathComponent(fileName)
    }

    public static func delete(fileName: String) {
        guard let url = try? url(for: fileName) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

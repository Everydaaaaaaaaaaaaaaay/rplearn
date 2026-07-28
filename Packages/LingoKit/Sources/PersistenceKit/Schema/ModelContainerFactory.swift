import Foundation
import SwiftData

public enum ModelContainerFactory {
    /// 当前开发期只有一个数据基线；若基线变化导致旧测试库无法打开，则重置本 App 的本地库。
    ///
    /// 首次正式发布前应移除这条回退路径，改为显式迁移计划。
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: LingoSchema.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            guard !inMemory else { throw error }
            try resetDevelopmentStore(at: configuration.url)
            return try ModelContainer(for: schema, configurations: [configuration])
        }
    }

    private static func resetDevelopmentStore(at storeURL: URL) throws {
        let fileManager = FileManager.default
        let storePaths = [
            storeURL.path,
            storeURL.path + "-shm",
            storeURL.path + "-wal",
        ]
        for path in storePaths where fileManager.fileExists(atPath: path) {
            try fileManager.removeItem(atPath: path)
        }
    }
}

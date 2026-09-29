import Foundation
import SwiftData

public enum ModelContainerFactory {
    /// 只打开当前模型；打开失败直接报错，不删除或重建已有文件。
    public static func makeContainer(
        inMemory: Bool = false,
        storeURL: URL? = nil
    ) throws -> ModelContainer {
        let schema = Schema(versionedSchema: LingoSchema.self)
        let configuration: ModelConfiguration
        if let storeURL, !inMemory {
            configuration = ModelConfiguration(schema: schema, url: storeURL)
        } else {
            configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: inMemory
            )
        }
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

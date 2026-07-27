import Foundation
import SwiftData

public enum ModelContainerFactory {
    /// 当前开发期只有一个数据基线；发布前可直接重置测试数据。
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: LingoSchema.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

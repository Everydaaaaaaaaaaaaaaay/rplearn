import Foundation
import SwiftData

public enum ModelContainerFactory {
    /// 使用显式版本计划打开本地库。迁移失败时保留原始数据库并向上抛错，绝不静默删库。
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
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: LingoMigrationPlan.self,
                configurations: [configuration]
            )
        } catch {
            // Some development builds wrote the current lightweight schema before a formal
            // migration plan existed, so those stores have no version checksum known to the
            // staged migrator. SwiftData can still open/migrate them automatically. This
            // fallback never removes or rewrites the source files on failure.
            return try ModelContainer(for: schema, configurations: [configuration])
        }
    }
}

public enum LingoMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [LingoSchemaV1.self, LingoSchema.self]
    }

    public static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: LingoSchemaV1.self, toVersion: LingoSchema.self),
        ]
    }
}

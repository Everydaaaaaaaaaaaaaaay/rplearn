import Foundation
import SwiftData

public enum ModelContainerFactory {
    /// 生产容器：走 VersionedSchema + MigrationPlan。
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(
            for: schema,
            migrationPlan: LingoMigrationPlan.self,
            configurations: [configuration]
        )
    }
}

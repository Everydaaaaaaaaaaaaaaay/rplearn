import Foundation
import SwiftData
import Testing
@testable import PersistenceKit

@Suite("SwiftData schema migration")
struct SchemaMigrationTests {
    @Test("1.0 角色、聊天和记忆升级到 1.1 时不丢失")
    func migratesVersionOneStoreWithoutDataLoss() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("lingotrip-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("LingoTrip.store")
        let characterID = UUID()
        let conversationID = UUID()
        let messageID = UUID()

        do {
            let oldSchema = Schema(versionedSchema: LingoSchemaV1.self)
            let oldConfiguration = ModelConfiguration(schema: oldSchema, url: storeURL)
            let oldContainer = try ModelContainer(
                for: oldSchema,
                configurations: [oldConfiguration]
            )
            let context = ModelContext(oldContainer)
            let character = LingoSchemaV1.CharacterEntity(
                characterID: characterID,
                name: "Migration Friend",
                age: 27,
                genderRaw: CharacterGender.other.rawValue,
                nationality: "British",
                regionID: "london",
                occupation: "archivist",
                hobbies: ["walking"],
                appearance: "green coat",
                personality: "careful and warm",
                difficultyLevelRaw: DifficultyLevel.junior3.rawValue,
                isFriend: true
            )
            let conversation = LingoSchemaV1.ConversationEntity(
                conversationID: conversationID,
                turnCount: 1
            )
            let message = LingoSchemaV1.MessageEntity(
                messageID: messageID,
                roleRaw: MessageRole.assistant.rawValue,
                text: "I remember our walk.",
                orderIndex: 0,
                tokenEstimate: 6
            )
            let memory = LingoSchemaV1.MemoryEntity(
                tierRaw: MemoryTier.long.rawValue,
                content: "They walked through the market together.",
                importance: 4
            )
            character.conversations.append(conversation)
            conversation.messages.append(message)
            character.memories.append(memory)
            context.insert(character)
            try context.save()
        }

        let currentSchema = Schema(versionedSchema: LingoSchema.self)
        let currentConfiguration = ModelConfiguration(schema: currentSchema, url: storeURL)
        let migratedContainer = try ModelContainer(
            for: currentSchema,
            migrationPlan: LingoMigrationPlan.self,
            configurations: [currentConfiguration]
        )
        let context = ModelContext(migratedContainer)
        let characters = try context.fetch(FetchDescriptor<CharacterEntity>())
        let conversations = try context.fetch(FetchDescriptor<ConversationEntity>())
        let messages = try context.fetch(FetchDescriptor<MessageEntity>())
        let memories = try context.fetch(FetchDescriptor<MemoryEntity>())

        let character = try #require(characters.first { $0.characterID == characterID })
        #expect(character.name == "Migration Friend")
        #expect(character.isFriend)
        #expect(character.travelerID == nil)
        #expect(character.contactStatusRaw == nil)
        #expect(character.proactiveMessagesEnabled)
        #expect(character.relationshipJSON == RelationshipSnapshot.initial.encodedJSON())
        #expect(character.growthJSON == CharacterGrowthSnapshot.initial.encodedJSON())
        #expect(conversations.contains { $0.conversationID == conversationID })
        #expect(messages.contains { $0.messageID == messageID && $0.text == "I remember our walk." })
        #expect(memories.contains {
            $0.content == "They walked through the market together."
                && $0.sourceRaw == MemorySource.chat.rawValue
        })
    }
}

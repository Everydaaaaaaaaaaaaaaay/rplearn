import Foundation
import SwiftData
import Testing
@testable import PersistenceKit

@Suite("当前 SwiftData 存储")
struct ModelContainerFactoryTests {
    @Test("当前模型创建与重开后保留角色、聊天、档案和记忆")
    func reopensCurrentStore() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("lingotrip-current-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("LingoTrip.store")
        let characterID = UUID()
        let conversationID = UUID()
        let messageID = UUID()
        var travelerID: String?

        do {
            let container = try ModelContainerFactory.makeContainer(storeURL: storeURL)
            let context = ModelContext(container)
            let character = CharacterEntity(
                characterID: characterID,
                name: "Current Friend",
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
            travelerID = character.travelerID
            let conversation = ConversationEntity(
                conversationID: conversationID,
                turnCount: 1
            )
            let message = MessageEntity(
                messageID: messageID,
                roleRaw: MessageRole.assistant.rawValue,
                text: "I remember our walk.",
                orderIndex: 0,
                tokenEstimate: 6
            )
            let memory = MemoryEntity(
                tierRaw: MemoryTier.long.rawValue,
                content: "They walked through the market together.",
                importance: 4
            )
            character.conversations.append(conversation)
            conversation.messages.append(message)
            character.memories.append(memory)
            context.insert(character)
            context.insert(UserProfileEntity(displayName: "保留档案", difficultyLevelRaw: "primary3"))
            try context.save()
        }

        let container = try ModelContainerFactory.makeContainer(storeURL: storeURL)
        let context = ModelContext(container)
        let profiles = try context.fetch(FetchDescriptor<UserProfileEntity>())
        #expect(profiles.first?.displayName == "保留档案")
        #expect(profiles.first?.difficultyLevelRaw == "primary3")
        let characters = try context.fetch(FetchDescriptor<CharacterEntity>())
        let conversations = try context.fetch(FetchDescriptor<ConversationEntity>())
        let messages = try context.fetch(FetchDescriptor<MessageEntity>())
        let memories = try context.fetch(FetchDescriptor<MemoryEntity>())

        let character = try #require(characters.first { $0.characterID == characterID })
        #expect(character.name == "Current Friend")
        #expect(character.isFriend)
        #expect(travelerID != nil)
        #expect(character.travelerID == travelerID)
        #expect(character.contactStatusRaw == ContactStatus.friend.rawValue)
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

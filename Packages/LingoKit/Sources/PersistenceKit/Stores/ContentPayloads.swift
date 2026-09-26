import Foundation
import CoreKit

struct ContentCharacterPayload: Codable {
    struct Card: Codable {
        let age: Int
        let appearance: String
        let avatarAssetName: String?
        var avatarId: String? = nil
        var avatarRemoteUrl: String? = nil
        let background: String?
        var birthday: String? = nil
        let gender: String
        let hobbies: [String]
        var hometown: String? = nil
        var languages: [String]? = nil
        let name: String
        let nationality: String
        let occupation: String
        let personality: String
        let regionId: String
        let speechStyle: String?
        var signature: String? = nil
        var readingVoice: CharacterReadingVoice? = nil
        var personaVoice: PersonaVoiceProfile? = nil
        var activityProfile: NPCActivityProfile? = nil

        init(
            age: Int,
            appearance: String,
            avatarAssetName: String?,
            avatarId: String? = nil,
            avatarRemoteUrl: String? = nil,
            background: String?,
            birthday: String? = nil,
            gender: String,
            hobbies: [String],
            hometown: String? = nil,
            languages: [String]? = nil,
            name: String,
            nationality: String,
            occupation: String,
            personality: String,
            regionId: String,
            speechStyle: String?,
            signature: String? = nil,
            personaVoice: PersonaVoiceProfile? = nil
        ) {
            self.age = age
            self.appearance = appearance
            self.avatarAssetName = avatarAssetName
            self.avatarId = avatarId
            self.avatarRemoteUrl = avatarRemoteUrl
            self.background = background
            self.birthday = birthday
            self.gender = gender
            self.hobbies = hobbies
            self.hometown = hometown
            self.languages = languages
            self.name = name
            self.nationality = nationality
            self.occupation = occupation
            self.personality = personality
            self.regionId = regionId
            self.speechStyle = speechStyle
            self.signature = signature
            self.personaVoice = personaVoice
            self.activityProfile = nil
        }
    }

    let card: Card
    let difficulty: String
    let isFriend: Bool
    var isFavorite: Bool? = nil
    let isMainCharacter: Bool
    let metAt: Date
    var relationship: RelationshipSnapshot? = nil
    var travelerId: String? = nil
    var publicIdentityRegistered: Bool? = nil
    var contactStatus: String? = nil
    var remarkName: String? = nil
    var privateNote: String? = nil
    var proactiveMessagesEnabled: Bool? = nil
    var mutedUntil: Date? = nil
    var growth: CharacterGrowthSnapshot? = nil
    var schemaVersion = 2
}

struct ContentConversationPayload: Codable {
    let createdAt: Date
    let isArchived: Bool
    let isEncounterSession: Bool
    var isPinned: Bool? = nil
    let lastMessageAt: Date
    var lastReadAt: Date? = nil
    let lastSummarizedMessageIndex: Int
    var schemaVersion = 2
    let turnCount: Int
}

struct ContentMessagePayload: Codable {
    var learningOrigin: LearningChatOrigin? = nil
    var audioAssetId: UUID? = nil
    let audioDuration: Double?
    let coachReviewJson: String?
    let createdAt: Date
    let isInterrupted: Bool
    let keywordRangesJson: String?
    let kind: String
    let orderIndex: Int
    let role: String
    var schemaVersion = 1
    let speechReviewJson: String?
    let text: String
    let tokenEstimate: Int
    let translationZh: String?
}

struct ContentFavoritePayload: Codable {
    let characterName: String
    let createdAt: Date
    var schemaVersion = 1
    let sentence: String
    let sourceMessageId: UUID?
    let translationZh: String?
}

struct ContentMemoryPayload: Codable {
    let content: String
    let createdAt: Date
    let importance: Int
    var source: String? = nil
    var schemaVersion = 2
    let sourceUpToIndex: Int
    let tier: String
}

struct ContentStoryProgressPayload: Codable {
    let completedAt: Date?
    let currentNodeId: String?
    let flags: [String: Bool]
    var schemaVersion = 1
}



struct LocalContentRecord: Codable, Sendable {
    let resourceType: ContentResourceKind
    let resourceID: String
    let parentID: String?
    let payloadJSON: String
}

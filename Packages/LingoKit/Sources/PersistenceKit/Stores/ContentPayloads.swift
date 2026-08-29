import Foundation

struct ContentCharacterPayload: Codable {
    struct Card: Codable {
        let age: Int
        let appearance: String
        let avatarAssetName: String?
        let background: String?
        let gender: String
        let hobbies: [String]
        let name: String
        let nationality: String
        let occupation: String
        let personality: String
        let regionId: String
        let speechStyle: String?
    }

    let card: Card
    let difficulty: String
    let isFriend: Bool
    var isFavorite: Bool? = nil
    let isMainCharacter: Bool
    let metAt: Date
    var relationship: RelationshipSnapshot? = nil
    var schemaVersion = 1
}

struct ContentConversationPayload: Codable {
    let createdAt: Date
    let isArchived: Bool
    let isEncounterSession: Bool
    let lastMessageAt: Date
    let lastSummarizedMessageIndex: Int
    let quizOptOut: Bool
    var schemaVersion = 1
    let turnCount: Int
    let turnsSinceQuiz: Int
}

struct ContentMessagePayload: Codable {
    var audioAssetId: UUID? = nil
    let audioDuration: Double?
    let coachReviewJson: String?
    let createdAt: Date
    let isInterrupted: Bool
    let keywordRangesJson: String?
    let kind: String
    let orderIndex: Int
    let quizChosenIndex: Int?
    let quizJson: String?
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
    var schemaVersion = 1
    let sourceUpToIndex: Int
    let tier: String
}

struct ContentStoryProgressPayload: Codable {
    let completedAt: Date?
    let currentNodeId: String?
    let flags: [String: Bool]
    var schemaVersion = 1
}

struct ContentQuizRecordPayload: Codable {
    let characterName: String?
    let chosenIndex: Int
    let correctIndex: Int
    let createdAt: Date
    let optionsJson: String
    let question: String
    var schemaVersion = 1
}

struct LocalContentRecord: Sendable {
    let resourceType: ContentResourceKind
    let resourceID: String
    let parentID: String?
    let payloadJSON: String
}

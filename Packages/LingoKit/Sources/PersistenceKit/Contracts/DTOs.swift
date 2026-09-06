import Foundation

/// 角色卡：定义角色的全部设定，用于 AI 角色扮演与形象展示。
/// 既是 main_characters.json 的解码目标，也是 AI 随机生成角色的结构化输出格式，
/// 原始 JSON 存入 CharacterEntity.cardJSON 供 prompt 复渲染。
public struct CharacterCard: Sendable, Codable, Equatable {
    public var name: String
    public var age: Int
    public var gender: CharacterGender
    public var nationality: String
    public var regionID: String
    public var occupation: String
    public var hobbies: [String]
    public var appearance: String
    public var personality: String
    /// 说话风格备注（口头禅、方言特色等），直接进 system prompt。
    public var speechStyle: String?
    /// 背景故事补充。
    public var background: String?
    public var avatarAssetName: String?
    /// 服务端头像库中的稳定标识与下载地址。已分配后不随同步重新匹配。
    public var avatarID: String?
    public var avatarRemoteURL: String?
    public var signature: String?
    /// 角色设定中的月日或完整 ISO 日期；虚构资料不与用户隐私混用。
    public var birthday: String?
    public var hometown: String?
    public var languages: [String]?
    public var personaVoice: PersonaVoiceProfile?

    public init(
        name: String,
        age: Int,
        gender: CharacterGender,
        nationality: String,
        regionID: String,
        occupation: String,
        hobbies: [String],
        appearance: String,
        personality: String,
        speechStyle: String? = nil,
        background: String? = nil,
        avatarAssetName: String? = nil,
        avatarID: String? = nil,
        avatarRemoteURL: String? = nil,
        signature: String? = nil,
        birthday: String? = nil,
        hometown: String? = nil,
        languages: [String]? = nil,
        personaVoice: PersonaVoiceProfile? = nil
    ) {
        self.name = name
        self.age = age
        self.gender = gender
        self.nationality = nationality
        self.regionID = regionID
        self.occupation = occupation
        self.hobbies = hobbies
        self.appearance = appearance
        self.personality = personality
        self.speechStyle = speechStyle
        self.background = background
        self.avatarAssetName = avatarAssetName
        self.avatarID = avatarID
        self.avatarRemoteURL = avatarRemoteURL
        self.signature = signature
        self.birthday = birthday
        self.hometown = hometown
        self.languages = languages
        self.personaVoice = personaVoice
    }

    public func encodedJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    public static func decode(fromJSON json: String) -> CharacterCard? {
        try? JSONDecoder().decode(CharacterCard.self, from: Data(json.utf8))
    }
}

/// 跨 actor 传递的角色快照。
public struct CharacterDTO: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var card: CharacterCard
    public var difficultyLevel: DifficultyLevel
    public var isMainCharacter: Bool
    public var isFriend: Bool
    public var metAt: Date
    public var isFavorite: Bool
    public var relationship: RelationshipSnapshot
    public var travelerID: String
    public var publicIdentityRegistered: Bool
    public var contactStatus: ContactStatus
    public var contactPreferences: ContactPreferences
    public var growth: CharacterGrowthSnapshot

    public init(
        id: UUID,
        card: CharacterCard,
        difficultyLevel: DifficultyLevel,
        isMainCharacter: Bool,
        isFriend: Bool,
        metAt: Date,
        isFavorite: Bool = false,
        relationship: RelationshipSnapshot = .initial,
        travelerID: String? = nil,
        publicIdentityRegistered: Bool = false,
        contactStatus: ContactStatus? = nil,
        contactPreferences: ContactPreferences = ContactPreferences(),
        growth: CharacterGrowthSnapshot = .initial
    ) {
        self.id = id
        self.card = card
        self.difficultyLevel = difficultyLevel
        self.isMainCharacter = isMainCharacter
        self.isFriend = isFriend
        self.metAt = metAt
        self.isFavorite = isFavorite
        self.relationship = relationship
        self.travelerID = travelerID ?? TravelerIDGenerator.make(from: id)
        self.publicIdentityRegistered = publicIdentityRegistered
        self.contactStatus = contactStatus ?? (isFriend ? .friend : .candidate)
        self.contactPreferences = contactPreferences
        self.growth = growth
    }

    public var displayName: String {
        let remark = contactPreferences.remarkName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return remark?.isEmpty == false ? remark! : card.name
    }
}

/// 跨 actor 传递的消息快照。
public struct MessageDTO: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var role: MessageRole
    public var kind: MessageKind
    public var text: String
    public var audioAssetID: UUID?
    public var audioFileName: String?
    public var audioDuration: Double?
    public var orderIndex: Int
    public var tokenEstimate: Int
    public var keywordRangesJSON: String?
    public var coachReviewJSON: String?
    public var speechReviewJSON: String?
    public var quizJSON: String?
    public var quizChosenIndex: Int?
    public var translationZh: String?
    public var isInterrupted: Bool
    public var createdAt: Date

    public init(
        id: UUID,
        role: MessageRole,
        kind: MessageKind,
        text: String,
        audioAssetID: UUID? = nil,
        audioFileName: String? = nil,
        audioDuration: Double? = nil,
        orderIndex: Int,
        tokenEstimate: Int = 0,
        keywordRangesJSON: String? = nil,
        coachReviewJSON: String? = nil,
        speechReviewJSON: String? = nil,
        quizJSON: String? = nil,
        quizChosenIndex: Int? = nil,
        translationZh: String? = nil,
        isInterrupted: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = id
        self.role = role
        self.kind = kind
        self.text = text
        self.audioAssetID = audioAssetID
        self.audioFileName = audioFileName
        self.audioDuration = audioDuration
        self.orderIndex = orderIndex
        self.tokenEstimate = tokenEstimate
        self.keywordRangesJSON = keywordRangesJSON
        self.coachReviewJSON = coachReviewJSON
        self.speechReviewJSON = speechReviewJSON
        self.quizJSON = quizJSON
        self.quizChosenIndex = quizChosenIndex
        self.translationZh = translationZh
        self.isInterrupted = isInterrupted
        self.createdAt = createdAt
    }
}

/// 跨 actor 传递的会话快照。
public struct ConversationDTO: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var characterID: UUID
    public var createdAt: Date
    public var lastMessageAt: Date
    public var turnCount: Int
    public var turnsSinceQuiz: Int
    public var quizOptOut: Bool
    public var lastSummarizedMessageIndex: Int
    public var isEncounterSession: Bool
    public var isArchived: Bool
    public var isPinned: Bool
    public var lastReadAt: Date?

    public init(
        id: UUID,
        characterID: UUID,
        createdAt: Date,
        lastMessageAt: Date,
        turnCount: Int,
        turnsSinceQuiz: Int,
        quizOptOut: Bool,
        lastSummarizedMessageIndex: Int,
        isEncounterSession: Bool,
        isArchived: Bool,
        isPinned: Bool = false,
        lastReadAt: Date? = nil
    ) {
        self.id = id
        self.characterID = characterID
        self.createdAt = createdAt
        self.lastMessageAt = lastMessageAt
        self.turnCount = turnCount
        self.turnsSinceQuiz = turnsSinceQuiz
        self.quizOptOut = quizOptOut
        self.lastSummarizedMessageIndex = lastSummarizedMessageIndex
        self.isEncounterSession = isEncounterSession
        self.isArchived = isArchived
        self.isPinned = isPinned
        self.lastReadAt = lastReadAt
    }
}

/// 用户档案快照。
public struct UserProfileDTO: Codable, Sendable, Equatable {
    public var displayName: String
    public var currentRegionID: String
    /// 首次选择伙伴所对应的起始城市；旅行后仍保持不变，用于恢复跨平台主线路线。
    public var starterRegionID: String?
    public var coins: Int
    public var subscriptionTier: SubscriptionTier
    public var friendSlotLimit: Int
    public var quizGloballyEnabled: Bool
    public var unlockedRegionIDs: [String]
    public var difficultyLevel: DifficultyLevel
    public var hasCompletedOnboarding: Bool
    public var learningGoal: LearningGoal
    public var studyStage: StudyStage?
    public var proficiencySource: ProficiencySource
    public var placementScore: Int?
    public var placementCompletedAt: Date?
    public var hasCompletedProfileSetup: Bool

    public init(
        displayName: String,
        currentRegionID: String,
        starterRegionID: String? = nil,
        coins: Int,
        subscriptionTier: SubscriptionTier,
        friendSlotLimit: Int,
        quizGloballyEnabled: Bool,
        unlockedRegionIDs: [String],
        difficultyLevel: DifficultyLevel,
        hasCompletedOnboarding: Bool,
        learningGoal: LearningGoal = .dailyConversation,
        studyStage: StudyStage? = nil,
        proficiencySource: ProficiencySource = .selfReported,
        placementScore: Int? = nil,
        placementCompletedAt: Date? = nil,
        hasCompletedProfileSetup: Bool = false
    ) {
        self.displayName = displayName
        self.currentRegionID = currentRegionID
        self.starterRegionID = starterRegionID
        self.coins = coins
        self.subscriptionTier = subscriptionTier
        self.friendSlotLimit = friendSlotLimit
        self.quizGloballyEnabled = quizGloballyEnabled
        self.unlockedRegionIDs = unlockedRegionIDs
        self.difficultyLevel = difficultyLevel
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.learningGoal = learningGoal
        self.studyStage = studyStage
        self.proficiencySource = proficiencySource
        self.placementScore = placementScore
        self.placementCompletedAt = placementCompletedAt
        self.hasCompletedProfileSetup = hasCompletedProfileSetup
    }
}

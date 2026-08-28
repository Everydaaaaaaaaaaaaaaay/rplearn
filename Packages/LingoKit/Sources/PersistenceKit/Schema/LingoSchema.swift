import Foundation
import SwiftData

/// 当前开发期 SwiftData 基线。所有写操作收敛到 @ModelActor 仓库，UI 用 @Query 只读。
public enum LingoSchema: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            UserProfileEntity.self,
            CharacterEntity.self,
            ConversationEntity.self,
            MessageEntity.self,
            MemoryEntity.self,
            FavoriteEntity.self,
            ItemEntity.self,
            TicketStubEntity.self,
            StoryProgressEntity.self,
            QuizRecordEntity.self,
            ContentSyncOwnerEntity.self,
            ContentSyncMetadataEntity.self,
            ContentOutboxEntity.self,
            VoiceMediaLinkEntity.self,
            VoiceMediaUploadEntity.self,
            JourneyStateEntity.self,
        ]
    }
}

extension LingoSchema {
    /// 用户档案（单例行）。
    @Model
    public final class UserProfileEntity {
        public var displayName: String
        public var currentRegionID: String
        public var coins: Int
        public var subscriptionTierRaw: String
        public var friendSlotLimit: Int
        public var quizGloballyEnabled: Bool
        public var unlockedRegionIDs: [String]
        public var difficultyLevelRaw: String
        public var hasCompletedOnboarding: Bool
        public var learningGoalRaw: String
        public var studyStageRaw: String?
        public var proficiencySourceRaw: String
        public var placementScore: Int?
        public var placementCompletedAt: Date?
        public var hasCompletedProfileSetup: Bool
        public var createdAt: Date

        public init(
            displayName: String = "",
            currentRegionID: String = "",
            coins: Int = 0,
            subscriptionTierRaw: String = SubscriptionTier.free.rawValue,
            friendSlotLimit: Int = 10,
            quizGloballyEnabled: Bool = true,
            unlockedRegionIDs: [String] = [],
            difficultyLevelRaw: String = DifficultyLevel.junior3.rawValue,
            hasCompletedOnboarding: Bool = false,
            learningGoalRaw: String = LearningGoal.dailyConversation.rawValue,
            studyStageRaw: String? = nil,
            proficiencySourceRaw: String = ProficiencySource.selfReported.rawValue,
            placementScore: Int? = nil,
            placementCompletedAt: Date? = nil,
            hasCompletedProfileSetup: Bool = false,
            createdAt: Date = .now
        ) {
            self.displayName = displayName
            self.currentRegionID = currentRegionID
            self.coins = coins
            self.subscriptionTierRaw = subscriptionTierRaw
            self.friendSlotLimit = friendSlotLimit
            self.quizGloballyEnabled = quizGloballyEnabled
            self.unlockedRegionIDs = unlockedRegionIDs
            self.difficultyLevelRaw = difficultyLevelRaw
            self.hasCompletedOnboarding = hasCompletedOnboarding
            self.learningGoalRaw = learningGoalRaw
            self.studyStageRaw = studyStageRaw
            self.proficiencySourceRaw = proficiencySourceRaw
            self.placementScore = placementScore
            self.placementCompletedAt = placementCompletedAt
            self.hasCompletedProfileSetup = hasCompletedProfileSetup
            self.createdAt = createdAt
        }
    }

    /// AI 角色。cardJSON 保存原始角色卡（CharacterCard），供 prompt 复渲染。
    @Model
    public final class CharacterEntity {
        @Attribute(.unique) public var characterID: UUID
        public var name: String
        public var age: Int
        public var genderRaw: String
        public var nationality: String
        public var regionID: String
        public var occupation: String
        public var hobbies: [String]
        public var appearance: String
        public var personality: String
        public var avatarAssetName: String?
        public var difficultyLevelRaw: String
        public var isMainCharacter: Bool
        public var isFriend: Bool
        public var isFavorite: Bool = false
        public var cardJSON: String
        public var metAt: Date

        @Relationship(deleteRule: .cascade, inverse: \ConversationEntity.character)
        public var conversations: [ConversationEntity]

        @Relationship(deleteRule: .cascade, inverse: \MemoryEntity.character)
        public var memories: [MemoryEntity]

        public init(
            characterID: UUID = UUID(),
            name: String,
            age: Int,
            genderRaw: String,
            nationality: String,
            regionID: String,
            occupation: String,
            hobbies: [String],
            appearance: String,
            personality: String,
            avatarAssetName: String? = nil,
            difficultyLevelRaw: String,
            isMainCharacter: Bool = false,
            isFriend: Bool = false,
            isFavorite: Bool = false,
            cardJSON: String = "",
            metAt: Date = .now
        ) {
            self.characterID = characterID
            self.name = name
            self.age = age
            self.genderRaw = genderRaw
            self.nationality = nationality
            self.regionID = regionID
            self.occupation = occupation
            self.hobbies = hobbies
            self.appearance = appearance
            self.personality = personality
            self.avatarAssetName = avatarAssetName
            self.difficultyLevelRaw = difficultyLevelRaw
            self.isMainCharacter = isMainCharacter
            self.isFriend = isFriend
            self.isFavorite = isFavorite
            self.cardJSON = cardJSON
            self.metAt = metAt
            self.conversations = []
            self.memories = []
        }
    }

    /// 会话：与同一角色的连续上下文。
    @Model
    public final class ConversationEntity {
        @Attribute(.unique) public var conversationID: UUID
        public var createdAt: Date
        public var lastMessageAt: Date
        public var turnCount: Int
        public var turnsSinceQuiz: Int
        public var quizOptOut: Bool
        public var lastSummarizedMessageIndex: Int
        public var isEncounterSession: Bool
        /// 偶遇未加好友离开后归档只读。
        public var isArchived: Bool

        public var character: CharacterEntity?

        @Relationship(deleteRule: .cascade, inverse: \MessageEntity.conversation)
        public var messages: [MessageEntity]

        public init(
            conversationID: UUID = UUID(),
            createdAt: Date = .now,
            lastMessageAt: Date = .now,
            turnCount: Int = 0,
            turnsSinceQuiz: Int = 0,
            quizOptOut: Bool = false,
            lastSummarizedMessageIndex: Int = 0,
            isEncounterSession: Bool = false,
            isArchived: Bool = false
        ) {
            self.conversationID = conversationID
            self.createdAt = createdAt
            self.lastMessageAt = lastMessageAt
            self.turnCount = turnCount
            self.turnsSinceQuiz = turnsSinceQuiz
            self.quizOptOut = quizOptOut
            self.lastSummarizedMessageIndex = lastSummarizedMessageIndex
            self.isEncounterSession = isEncounterSession
            self.isArchived = isArchived
            self.messages = []
        }
    }

    /// 消息。orderIndex 显式排序（SwiftData 关系数组无顺序保证）。
    @Model
    public final class MessageEntity {
        @Attribute(.unique) public var messageID: UUID
        public var roleRaw: String
        public var kindRaw: String
        public var text: String
        public var audioFileName: String?
        public var audioDuration: Double?
        public var orderIndex: Int
        public var tokenEstimate: Int
        public var keywordRangesJSON: String?
        public var coachReviewJSON: String?
        /// 口语点评（语音消息）。
        public var speechReviewJSON: String?
        public var quizJSON: String?
        /// 已作答的 quiz 选项下标（nil 表示未作答）。
        public var quizChosenIndex: Int?
        /// 整句翻译缓存。
        public var translationZh: String?
        /// 流式中断标记（已收增量落库，气泡提供重试）。
        public var isInterrupted: Bool
        public var createdAt: Date

        public var conversation: ConversationEntity?

        public init(
            messageID: UUID = UUID(),
            roleRaw: String,
            kindRaw: String = MessageKind.text.rawValue,
            text: String,
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
            self.messageID = messageID
            self.roleRaw = roleRaw
            self.kindRaw = kindRaw
            self.text = text
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

    /// 分级记忆条目（单条事实）。
    @Model
    public final class MemoryEntity {
        public var tierRaw: String
        public var content: String
        /// 1-5，越大越重要。
        public var importance: Int
        /// 该记忆覆盖到的消息 orderIndex 上界。
        public var sourceUpToIndex: Int
        public var createdAt: Date

        public var character: CharacterEntity?

        public init(
            tierRaw: String,
            content: String,
            importance: Int = 3,
            sourceUpToIndex: Int = 0,
            createdAt: Date = .now
        ) {
            self.tierRaw = tierRaw
            self.content = content
            self.importance = importance
            self.sourceUpToIndex = sourceUpToIndex
            self.createdAt = createdAt
        }
    }

    /// 收藏快照：兼容旧版句子收藏，单词与语法点以 characterName 内部标记区分。
    @Model
    public final class FavoriteEntity {
        @Attribute(.unique) public var favoriteID: UUID
        public var sentence: String
        public var sourceMessageID: UUID?
        public var characterName: String
        public var translationZh: String?
        public var createdAt: Date

        public init(
            favoriteID: UUID = UUID(),
            sentence: String,
            sourceMessageID: UUID? = nil,
            characterName: String,
            translationZh: String? = nil,
            createdAt: Date = .now
        ) {
            self.favoriteID = favoriteID
            self.sentence = sentence
            self.sourceMessageID = sourceMessageID
            self.characterName = characterName
            self.translationZh = translationZh
            self.createdAt = createdAt
        }
    }

    /// 道具（机票）。
    @Model
    public final class ItemEntity {
        @Attribute(.unique) public var itemID: UUID
        public var typeRaw: String
        public var countryCode: String?
        public var sourceRaw: String
        public var createdAt: Date
        public var consumedAt: Date?

        public init(
            itemID: UUID = UUID(),
            typeRaw: String,
            countryCode: String? = nil,
            sourceRaw: String,
            createdAt: Date = .now,
            consumedAt: Date? = nil
        ) {
            self.itemID = itemID
            self.typeRaw = typeRaw
            self.countryCode = countryCode
            self.sourceRaw = sourceRaw
            self.createdAt = createdAt
            self.consumedAt = consumedAt
        }
    }

    /// 票根：首次抵达目的地时生成，artSeed 决定纪念票根配色。
    @Model
    public final class TicketStubEntity {
        @Attribute(.unique) public var stubID: UUID
        public var fromRegionID: String
        public var toRegionID: String
        public var usedAt: Date
        public var serialNumber: String
        public var artSeed: Int

        public init(
            stubID: UUID = UUID(),
            fromRegionID: String,
            toRegionID: String,
            usedAt: Date = .now,
            serialNumber: String,
            artSeed: Int
        ) {
            self.stubID = stubID
            self.fromRegionID = fromRegionID
            self.toRegionID = toRegionID
            self.usedAt = usedAt
            self.serialNumber = serialNumber
            self.artSeed = artSeed
        }
    }

    /// 剧情进度（断点续播）。
    @Model
    public final class StoryProgressEntity {
        @Attribute(.unique) public var storyID: String
        public var currentNodeID: String?
        public var flagsJSON: String
        public var completedAt: Date?

        public init(storyID: String, currentNodeID: String? = nil, flagsJSON: String = "{}", completedAt: Date? = nil) {
            self.storyID = storyID
            self.currentNodeID = currentNodeID
            self.flagsJSON = flagsJSON
            self.completedAt = completedAt
        }
    }

    /// 出题记录。
    @Model
    public final class QuizRecordEntity {
        public var question: String
        public var optionsJSON: String
        public var correctIndex: Int
        public var chosenIndex: Int?
        public var characterName: String?
        public var createdAt: Date

        public init(
            question: String,
            optionsJSON: String,
            correctIndex: Int,
            chosenIndex: Int? = nil,
            characterName: String? = nil,
            createdAt: Date = .now
        ) {
            self.question = question
            self.optionsJSON = optionsJSON
            self.correctIndex = correctIndex
            self.chosenIndex = chosenIndex
            self.characterName = characterName
            self.createdAt = createdAt
        }
    }
}

// 顶层别名，调用方免写 LingoSchema 前缀。
public typealias UserProfileEntity = LingoSchema.UserProfileEntity
public typealias CharacterEntity = LingoSchema.CharacterEntity
public typealias ConversationEntity = LingoSchema.ConversationEntity
public typealias MessageEntity = LingoSchema.MessageEntity
public typealias MemoryEntity = LingoSchema.MemoryEntity
public typealias FavoriteEntity = LingoSchema.FavoriteEntity
public typealias ItemEntity = LingoSchema.ItemEntity
public typealias TicketStubEntity = LingoSchema.TicketStubEntity
public typealias StoryProgressEntity = LingoSchema.StoryProgressEntity
public typealias QuizRecordEntity = LingoSchema.QuizRecordEntity

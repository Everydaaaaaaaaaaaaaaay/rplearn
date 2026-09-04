import Foundation

/// 角色在当前用户名册中的状态。公共 NPC 身份与每位用户的联系人关系分离。
public enum ContactStatus: String, Sendable, Codable, CaseIterable {
    /// 已生成或遇见，但尚未成为好友。
    case candidate
    /// 当前好友。
    case friend
    /// 用户明确移除；剧情重建不能静默恢复。
    case removed
}

public enum MemorySource: String, Sendable, Codable, CaseIterable {
    case chat
    case story
    case activity
}

/// 结构化人格锚点。它描述角色稳定的表达方式，不承载用户私有关系或聊天记忆。
public struct PersonaVoiceProfile: Sendable, Codable, Equatable {
    public var values: [String]
    public var flaws: [String]
    public var conversationalHabits: [String]
    public var boundaries: [String]
    public var anchorLines: [String]

    public init(
        values: [String] = [],
        flaws: [String] = [],
        conversationalHabits: [String] = [],
        boundaries: [String] = [],
        anchorLines: [String] = []
    ) {
        self.values = values
        self.flaws = flaws
        self.conversationalHabits = conversationalHabits
        self.boundaries = boundaries
        self.anchorLines = anchorLines
    }
}

/// 可被真实互动缓慢影响的倾向。基础人格不会被覆盖，成长只作为关系分支上的增量。
public enum CharacterGrowthTrait: String, Sendable, Codable, CaseIterable {
    case impulsivity
    case patience
    case assertiveness
    case openness
    case selfConfidence
    case emotionalExpression
    case flexibility
    case responsibility

    public var titleZh: String {
        switch self {
        case .impulsivity: "冲动倾向"
        case .patience: "耐心"
        case .assertiveness: "表达立场"
        case .openness: "开放程度"
        case .selfConfidence: "自信"
        case .emotionalExpression: "情感表达"
        case .flexibility: "灵活性"
        case .responsibility: "责任感"
        }
    }
}

public enum CharacterGrowthDirection: String, Sendable, Codable, CaseIterable {
    case increase
    case decrease
}

public enum CharacterGrowthStage: String, Sendable, Codable, CaseIterable {
    case considering
    case experimenting
    case integrating
    case established

    public var titleZh: String {
        switch self {
        case .considering: "开始思考"
        case .experimenting: "正在尝试"
        case .integrating: "逐渐形成习惯"
        case .established: "已经沉淀"
        }
    }
}

public struct CharacterGrowthArc: Sendable, Codable, Equatable, Identifiable {
    public var id: UUID
    public var trait: CharacterGrowthTrait
    public var direction: CharacterGrowthDirection
    /// 0...1 的关系分支成长进度，不等同于基础人格强度。
    public var progress: Double
    public var stage: CharacterGrowthStage
    public var reasonZh: String
    public var evidenceMessageIDs: [UUID]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        trait: CharacterGrowthTrait,
        direction: CharacterGrowthDirection,
        progress: Double = 0,
        stage: CharacterGrowthStage = .considering,
        reasonZh: String,
        evidenceMessageIDs: [UUID] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.trait = trait
        self.direction = direction
        self.progress = progress
        self.stage = stage
        self.reasonZh = reasonZh
        self.evidenceMessageIDs = evidenceMessageIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct CharacterGrowthSnapshot: Sendable, Codable, Equatable {
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var revision: Int
    /// 用户暂停后保留既有成长，但不再从新互动中吸收成长证据。
    public var isPaused: Bool
    public var arcs: [CharacterGrowthArc]

    public init(
        schemaVersion: Int = CharacterGrowthSnapshot.currentSchemaVersion,
        revision: Int = 0,
        isPaused: Bool = false,
        arcs: [CharacterGrowthArc] = []
    ) {
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.isPaused = isPaused
        self.arcs = arcs
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case revision
        case isPaused
        case arcs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        revision = try container.decodeIfPresent(Int.self, forKey: .revision) ?? 0
        // v1 快照没有该字段；升级时必须延续原先“允许成长”的行为。
        isPaused = try container.decodeIfPresent(Bool.self, forKey: .isPaused) ?? false
        arcs = try container.decodeIfPresent([CharacterGrowthArc].self, forKey: .arcs) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(revision, forKey: .revision)
        try container.encode(isPaused, forKey: .isPaused)
        try container.encode(arcs, forKey: .arcs)
    }

    public static var initial: CharacterGrowthSnapshot { CharacterGrowthSnapshot() }

    public func encodedJSON() -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    public static func decode(fromJSON json: String) -> CharacterGrowthSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Self.self, from: Data(json.utf8))
    }
}

/// 用户可编辑的联系人偏好。特别关心继续使用 CharacterDTO.isFavorite 以兼容现有 UI。
public struct ContactPreferences: Sendable, Codable, Equatable {
    public var remarkName: String?
    public var privateNote: String?
    public var proactiveMessagesEnabled: Bool
    public var mutedUntil: Date?

    public init(
        remarkName: String? = nil,
        privateNote: String? = nil,
        proactiveMessagesEnabled: Bool = true,
        mutedUntil: Date? = nil
    ) {
        self.remarkName = remarkName
        self.privateNote = privateNote
        self.proactiveMessagesEnabled = proactiveMessagesEnabled
        self.mutedUntil = mutedUntil
    }

    public func isMuted(at date: Date = .now) -> Bool {
        guard let mutedUntil else { return false }
        return mutedUntil > date
    }
}

/// 可读旅伴号的端侧稳定兜底。公共社区上线后仍由服务端登记并保证唯一。
public enum TravelerIDGenerator {
    public static func make(from id: UUID) -> String {
        let bytes = withUnsafeBytes(of: id.uuid) { Array($0) }
        // FNV-1a 保证同一 UUID 跨启动得到同一号码，不依赖 Swift Hasher 随机种子。
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in bytes {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        let body = String(format: "%010llu", hash % 10_000_000_000)
        return body + String(checkDigit(for: body))
    }

    public static func isValid(_ value: String) -> Bool {
        guard value.count == 11,
              value.allSatisfy(\.isNumber),
              let final = value.last?.wholeNumberValue
        else { return false }
        return final == checkDigit(for: String(value.dropLast()))
    }

    private static func checkDigit(for body: String) -> Int {
        let digits = body.compactMap(\.wholeNumberValue)
        let sum = digits.reversed().enumerated().reduce(0) { partial, pair in
            let (index, digit) = pair
            let multiplied = index.isMultiple(of: 2) ? digit * 2 : digit
            return partial + (multiplied > 9 ? multiplied - 9 : multiplied)
        }
        return (10 - sum % 10) % 10
    }
}

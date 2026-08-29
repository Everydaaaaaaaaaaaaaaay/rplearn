import Foundation

/// 用户与角色的关系是多维、连续的；`affinity` 只是面向用户的 0...150 投影。
///
/// 关系状态跟随角色一起同步。所有数值都使用稳定范围，便于未来升级算法时迁移。
public struct RelationshipSnapshot: Sendable, Codable, Equatable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    /// 最近一次结算后的关系温度，范围 0...150。
    public var affinity: Double
    /// 时间不活跃时的渐近下限。它代表已经沉淀的共同历史，不会仅因失联而消失。
    public var bondFloor: Double
    public var familiarity: Double
    public var trust: Double
    public var rapport: Double
    public var care: Double
    public var respect: Double
    /// 尚未修复的关系张力，范围 0...1。
    public var unresolvedStrain: Double
    public var interactionCount: Int
    public var meaningfulInteractionCount: Int
    /// 抗刷取所需的当日互动聚合，只保留计数与正向总收益，不保存消息内容。
    public var activityDayStart: Date?
    public var activityCountToday: Int
    /// 普通正向互动的当日累计；修复使用独立额度，避免已达普通上限后无法道歉。
    public var positiveGainToday: Double
    /// 当日关系修复恢复量。可选以兼容首版快照。
    public var repairGainToday: Double?
    public var lastInteractionAt: Date?
    public var lastEvaluatedMessageID: UUID?
    /// 跨会话的结算游标。消息在新会话中会从 0 重新编号，因此不能只依赖 orderIndex。
    public var lastEvaluatedMessageAt: Date?
    public var lastEvaluatedOrderIndex: Int
    /// 近期已经结算的消息 ID。允许不同消息乱序完成，同时阻止任何一条重复结算。
    public var recentEvaluatedMessageIDs: [UUID]?
    /// 乐观并发版本，避免多个后台点评互相覆盖。
    public var revision: Int
    /// 仅保留少量最近变化，用于解释分数而不是制造永久评判档案。
    public var recentEvents: [RelationshipEventRecord]

    public init(
        schemaVersion: Int = RelationshipSnapshot.currentSchemaVersion,
        affinity: Double = 10,
        bondFloor: Double = 5,
        familiarity: Double = 0.08,
        trust: Double = 0.12,
        rapport: Double = 0.10,
        care: Double = 0.10,
        respect: Double = 0.50,
        unresolvedStrain: Double = 0,
        interactionCount: Int = 0,
        meaningfulInteractionCount: Int = 0,
        activityDayStart: Date? = nil,
        activityCountToday: Int = 0,
        positiveGainToday: Double = 0,
        repairGainToday: Double? = 0,
        lastInteractionAt: Date? = nil,
        lastEvaluatedMessageID: UUID? = nil,
        lastEvaluatedMessageAt: Date? = nil,
        lastEvaluatedOrderIndex: Int = -1,
        recentEvaluatedMessageIDs: [UUID]? = [],
        revision: Int = 0,
        recentEvents: [RelationshipEventRecord] = []
    ) {
        self.schemaVersion = schemaVersion
        self.affinity = affinity
        self.bondFloor = bondFloor
        self.familiarity = familiarity
        self.trust = trust
        self.rapport = rapport
        self.care = care
        self.respect = respect
        self.unresolvedStrain = unresolvedStrain
        self.interactionCount = interactionCount
        self.meaningfulInteractionCount = meaningfulInteractionCount
        self.activityDayStart = activityDayStart
        self.activityCountToday = activityCountToday
        self.positiveGainToday = positiveGainToday
        self.repairGainToday = repairGainToday
        self.lastInteractionAt = lastInteractionAt
        self.lastEvaluatedMessageID = lastEvaluatedMessageID
        self.lastEvaluatedMessageAt = lastEvaluatedMessageAt
        self.lastEvaluatedOrderIndex = lastEvaluatedOrderIndex
        self.recentEvaluatedMessageIDs = recentEvaluatedMessageIDs
        self.revision = revision
        self.recentEvents = recentEvents
    }

    public static var initial: RelationshipSnapshot { RelationshipSnapshot() }

    /// 不写库的时间投影。指数衰减只作用于高于长期纽带下限的部分。
    public func projectedAffinity(at date: Date = .now) -> Double {
        guard let lastInteractionAt, date > lastInteractionAt else {
            return Self.clamp(affinity, to: 0...150)
        }
        let inactiveDays = date.timeIntervalSince(lastInteractionAt) / 86_400
        let graceDays = 4 + (14 * Self.clamp(familiarity, to: 0...1))
        guard inactiveDays > graceDays else {
            return Self.clamp(affinity, to: 0...150)
        }

        let floor = Self.clamp(min(bondFloor, affinity), to: 0...120)
        let halfLifeDays = 24
            + (150 * pow(Self.clamp(floor / 120, to: 0...1), 0.85))
            + (50 * Self.clamp(familiarity, to: 0...1))
        let activePart = max(affinity - floor, 0)
        let multiplier = pow(0.5, (inactiveDays - graceDays) / halfLifeDays)
        return Self.clamp(floor + activePart * multiplier, to: 0...150)
    }

    public var displayAffinity: Int {
        Int(projectedAffinity().rounded())
    }

    public var latestEvent: RelationshipEventRecord? {
        recentEvents.max { $0.createdAt < $1.createdAt }
    }

    public func encodedJSON() -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    public static func decode(fromJSON json: String) -> RelationshipSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Self.self, from: Data(json.utf8))
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, value))
    }
}

public struct RelationshipEventRecord: Sendable, Codable, Equatable, Identifiable {
    public enum Source: String, Sendable, Codable, CaseIterable {
        case textChat
        case voiceChat
        case sharedActivity
        case story
    }

    public var id: UUID
    public var source: Source
    public var delta: Double
    public var reasonZh: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        source: Source,
        delta: Double,
        reasonZh: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.source = source
        self.delta = delta
        self.reasonZh = reasonZh
        self.createdAt = createdAt
    }
}

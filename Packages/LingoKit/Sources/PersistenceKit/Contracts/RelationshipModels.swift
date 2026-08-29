import Foundation

/// 用户与角色的关系是多维、连续的；`affinity` 只是面向用户的 0...150 投影。
///
/// 关系状态跟随角色一起同步。所有数值都使用稳定范围，便于未来升级算法时迁移。
public struct RelationshipSnapshot: Sendable, Codable, Equatable {
    public static let currentSchemaVersion = 3

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
    /// 最近一次确实包含可判断社会信息的互动。空白、重复心跳或模型失败不能刷新关系衰减时钟。
    public var lastSubstantiveInteractionAt: Date?
    /// 对近期互动质量的指数平滑预期，范围 -1...1；只用于估计关系的一致性，不对用户作人格判断。
    public var expectedSocialQuality: Double?
    /// 近期互动是否稳定、可预测，范围 0...1。单次互动不足以形成高稳定性。
    public var interactionStability: Double?
    /// 这段关系自身的有效联系间隔（天）的稳健指数平均。只学习跨会话间隔，不记录消息内容。
    public var typicalContactIntervalDays: Double?
    /// 已吸收的跨会话间隔样本数。至少两个样本后，联系节律才参与时间投影。
    public var substantiveIntervalSampleCount: Int?
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
        lastSubstantiveInteractionAt: Date? = nil,
        expectedSocialQuality: Double? = nil,
        interactionStability: Double? = nil,
        typicalContactIntervalDays: Double? = nil,
        substantiveIntervalSampleCount: Int? = nil,
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
        // 直接构造带最后联系时间的当前快照时，默认该时间来自一次有效互动；引擎的空洞兜底路径会显式保留 nil。
        self.lastSubstantiveInteractionAt = lastSubstantiveInteractionAt ?? lastInteractionAt
        self.expectedSocialQuality = expectedSocialQuality
        self.interactionStability = interactionStability
        self.typicalContactIntervalDays = typicalContactIntervalDays
        self.substantiveIntervalSampleCount = substantiveIntervalSampleCount
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
        // 旧快照没有有效联系字段时回退到旧的最后联系时间；下一次结算会自然补齐迁移锚点。
        let legacyAnchor = schemaVersion < 2 ? lastInteractionAt : nil
        guard let decayAnchor = lastSubstantiveInteractionAt ?? legacyAnchor,
              date > decayAnchor
        else {
            return Self.clamp(affinity, to: 0...150)
        }
        let inactiveDays = date.timeIntervalSince(decayAnchor) / 86_400
        // 联系节律只能在至少两个跨会话间隔后生效，且有严格上限。它让低频但稳定的关系获得合理宽限，
        // 不能让一次超长失联永久改变衰减，也不能消除时间效应。
        let cadenceSampleCount = max(substantiveIntervalSampleCount ?? 0, 0)
        let reliableCadence: Double
        if cadenceSampleCount >= 2, let typicalContactIntervalDays {
            reliableCadence = Self.clamp(typicalContactIntervalDays, to: 1...45)
        } else {
            reliableCadence = 0
        }
        let graceDays = 4
            + (14 * Self.clamp(familiarity, to: 0...1))
            + (0.75 * reliableCadence)
        guard inactiveDays > graceDays else {
            return Self.clamp(affinity, to: 0...150)
        }

        let floor = Self.clamp(min(bondFloor, affinity), to: 0...120)
        let halfLifeDays = 24
            + (150 * pow(Self.clamp(floor / 120, to: 0...1), 0.85))
            + (50 * Self.clamp(familiarity, to: 0...1))
            + min(45, 1.5 * reliableCadence)
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

import Foundation

/// 一次互动中，从角色视角观察到的社会信号。语言水平不属于关系质量维度。
public struct RelationshipSignal: Sendable, Codable, Equatable {
    public var warmth: Double
    public var responsiveness: Double
    public var respect: Double
    public var empathy: Double
    public var reciprocity: Double
    public var disclosure: Double
    public var resonance: Double
    public var engagement: Double
    public var boundaryHarm: Double
    public var repair: Double
    public var significance: Double
    public var confidence: Double
    public var reasonZh: String

    public init(
        warmth: Double,
        responsiveness: Double,
        respect: Double,
        empathy: Double,
        reciprocity: Double,
        disclosure: Double,
        resonance: Double,
        engagement: Double,
        boundaryHarm: Double,
        repair: Double,
        significance: Double,
        confidence: Double,
        reasonZh: String
    ) {
        self.warmth = warmth
        self.responsiveness = responsiveness
        self.respect = respect
        self.empathy = empathy
        self.reciprocity = reciprocity
        self.disclosure = disclosure
        self.resonance = resonance
        self.engagement = engagement
        self.boundaryHarm = boundaryHarm
        self.repair = repair
        self.significance = significance
        self.confidence = confidence
        self.reasonZh = reasonZh
    }
}

public struct InteractionReview: Sendable, Codable, Equatable {
    public var coachReview: CoachReview
    public var relationship: RelationshipSignal
    public var growth: CharacterGrowthSignal?
    public var quiz: Quiz? = nil
}

/// 领域枚举。实体内一律以 String rawValue 落库（SwiftData 枚举演进更安全）。

/// 难度/熟练度等级，按中国学制细分（plan.md §2）。
public enum DifficultyLevel: String, Sendable, Codable, CaseIterable {
    case primary1, primary2, primary3, primary4, primary5, primary6
    case junior1, junior2, junior3
    case senior1, senior2, senior3
    case undergraduate
    case postgraduate
    case advanced

    public var displayName: String {
        switch self {
        case .primary1: "小学一年级"
        case .primary2: "小学二年级"
        case .primary3: "小学三年级"
        case .primary4: "小学四年级"
        case .primary5: "小学五年级"
        case .primary6: "小学六年级"
        case .junior1: "初中一年级"
        case .junior2: "初中二年级"
        case .junior3: "初中三年级"
        case .senior1: "高中一年级"
        case .senior2: "高中二年级"
        case .senior3: "高中三年级"
        case .undergraduate: "大学本科"
        case .postgraduate: "研究生"
        case .advanced: "更高"
        }
    }

    /// 词频阈值：角色回复中排名超过该值的词视为「关键词」划线（plan.md §3.8）。
    public var keywordFrequencyThreshold: Int {
        switch self {
        case .primary1, .primary2, .primary3, .primary4, .primary5, .primary6: 3000
        case .junior1, .junior2, .junior3: 6000
        case .senior1, .senior2, .senior3: 10000
        case .undergraduate: 15000
        case .postgraduate, .advanced: 25000
        }
    }
}

/// 服务端统一权益系统返回的订阅等级；本地字段仅作为离线显示缓存。
public enum SubscriptionTier: String, Sendable, Codable, CaseIterable {
    case free
    case plus
    case pro

    public var displayName: String {
        switch self {
        case .free: "免费版"
        case .plus: "Plus"
        case .pro: "Pro"
        }
    }
}

public enum MessageRole: String, Sendable, Codable {
    case user
    case assistant
    case coach
}

public enum MessageKind: String, Sendable, Codable {
    case text
    case voice
    case quiz
    case storyLine
}

public enum MemoryTier: String, Sendable, Codable, CaseIterable {
    case short
    case mid
    case long
}

public enum CharacterGender: String, Sendable, Codable, CaseIterable {
    case male
    case female
    case other
}

public enum ItemType: String, Sendable, Codable {
    /// 通用机票：可解锁任意未到访地区。
    case ticketUniversal
    /// 指定国家机票：只能解锁 countryCode 匹配的未到访地区。
    case ticketCountry
}

public enum ItemSource: String, Sendable, Codable {
    case story
    case quest
    case purchase
    case subscription
    case support
    case debug
}

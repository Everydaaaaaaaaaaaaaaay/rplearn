/// 领域枚举。实体内一律以 String rawValue 落库（SwiftData 枚举演进更安全）。

/// 难度/熟练度等级，按中国学制细分。
public enum DifficultyLevel: String, Sendable, Codable, CaseIterable {
    case kindergarten
    case primary1, primary2, primary3, primary4, primary5, primary6
    case junior1, junior2, junior3
    case senior1, senior2, senior3
    case undergraduate
    case postgraduate
    case advanced

    public var displayName: String {
        switch self {
        case .kindergarten: "幼儿启蒙"
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
        case .undergraduate: "大学英语四级"
        case .postgraduate: "大学英语六级"
        case .advanced: "高级英语（专业与学术）"
        }
    }

    /// 对外展示的中国英语能力等级量表参考区间。
    ///
    /// 年级、人教版教材进度、CET 与 CSE 并不存在逐级官方等值关系，
    /// 因此这里只用于解释测评结果，不表示获得任何考试认证。
    public var cseReference: String {
        switch self {
        case .kindergarten: "CSE 一级以下"
        case .primary1, .primary2, .primary3: "CSE 一级起步"
        case .primary4, .primary5, .primary6: "CSE 一至二级"
        case .junior1, .junior2, .junior3: "CSE 二至三级"
        case .senior1, .senior2, .senior3: "CSE 三至四级"
        case .undergraduate: "CSE 四至五级参考"
        case .postgraduate: "CSE 五至六级参考"
        case .advanced: "CSE 七级及以上参考"
        }
    }

    /// 测评等级在由低至高序列中的位置，用于计算相邻等级稳定度。
    public var placementOrdinal: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }

    /// 词频阈值：角色回复中排名超过该值的词视为「关键词」划线。
    public var keywordFrequencyThreshold: Int {
        switch self {
        case .kindergarten: 1000
        case .primary1, .primary2, .primary3, .primary4, .primary5, .primary6: 3000
        case .junior1, .junior2, .junior3: 6000
        case .senior1, .senior2, .senior3: 10000
        case .undergraduate: 15000
        case .postgraduate, .advanced: 25000
        }
    }
}

/// 用户最希望优先提升的英语使用场景。
public enum LearningGoal: String, Sendable, Codable, CaseIterable {
    case dailyConversation
    case travel
    case school
    case exam
    case studyAbroad
    case work
    case culture

    public var displayName: String {
        switch self {
        case .dailyConversation: "日常交流"
        case .travel: "旅行沟通"
        case .school: "跟上学校课程"
        case .exam: "备考提分"
        case .studyAbroad: "留学准备"
        case .work: "职场英语"
        case .culture: "认识朋友与文化"
        }
    }
}

/// 当前所处学段。它只帮助解释学习语境，不直接等同于英语水平。
public enum StudyStage: String, Sendable, Codable, CaseIterable {
    case primary
    case juniorHigh
    case seniorHigh
    case university
    case postgraduate
    case working
    case other

    public var displayName: String {
        switch self {
        case .primary: "小学"
        case .juniorHigh: "初中"
        case .seniorHigh: "高中"
        case .university: "大学"
        case .postgraduate: "研究生"
        case .working: "已工作"
        case .other: "其他"
        }
    }
}

/// 当前英语等级的最近一次来源。
public enum ProficiencySource: String, Sendable, Codable {
    case selfReported
    case placement
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

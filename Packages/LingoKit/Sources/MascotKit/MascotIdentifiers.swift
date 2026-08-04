import Foundation

/// 吉祥物资产的稳定标识。业务层不依赖磁盘文件名。
public struct MascotAssetID: RawRepresentable, Hashable, Sendable, Codable,
    ExpressibleByStringLiteral
{
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }
}

public extension MascotAssetID {
    static let gugu: Self = "gugu"
}

/// 动画片段的稳定标识，对应资源包中的 clip 名称。
public struct MascotAnimationID: RawRepresentable, Hashable, Sendable, Codable,
    ExpressibleByStringLiteral
{
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }
}

public extension MascotAnimationID {
    static let idle: Self = "GUGU_IDLE_LOOP"
    static let celebrate: Self = "GUGU_CELEBRATE"
    static let talk: Self = "GUGU_TALK_LOOP"
}

/// 面向产品含义的动画语义。它是可扩展字符串，而非封闭枚举。
public struct MascotAnimationSemantic: RawRepresentable, Hashable, Sendable, Codable,
    ExpressibleByStringLiteral
{
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }
}

public extension MascotAnimationSemantic {
    static let idle: Self = "idle"
    static let success: Self = "success"
    static let speaking: Self = "speaking"
}

/// 应用事件与动画之间的可配置映射键。
public struct MascotEventID: RawRepresentable, Hashable, Sendable, Codable,
    ExpressibleByStringLiteral
{
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }
}

public extension MascotEventID {
    static let lessonIdle: Self = "lesson_idle"
    static let answerCorrect: Self = "answer_correct"
    static let speechStarted: Self = "tts_started"
    static let speechFinished: Self = "tts_finished"
}

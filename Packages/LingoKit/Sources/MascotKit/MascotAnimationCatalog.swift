import Foundation

/// Blender 源帧或运行时帧的闭区间。
public struct MascotFrameRange: Equatable, Sendable, Codable {
    public let lowerBound: Int
    public let upperBound: Int

    public init(lowerBound: Int, upperBound: Int) {
        self.lowerBound = lowerBound
        self.upperBound = upperBound
    }

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        lowerBound = try container.decode(Int.self)
        upperBound = try container.decode(Int.self)
        guard container.isAtEnd else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "帧区间必须恰好包含起始和结束两个整数"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(lowerBound)
        try container.encode(upperBound)
    }
}

/// 单个动画片段的运行参数。交叉淡化与回落动作由资产侧声明。
public struct MascotAnimationClip: Equatable, Sendable, Codable {
    public let semantic: MascotAnimationSemantic
    public let sourceFrames: MascotFrameRange
    public let runtimeFrames: MascotFrameRange
    public let duration: TimeInterval
    public let repeats: Bool
    public let returnTo: MascotAnimationID?
    public let crossfadeIn: TimeInterval
    public let crossfadeOut: TimeInterval

    enum CodingKeys: String, CodingKey {
        case semantic
        case sourceFrames = "source_frames"
        case runtimeFrames = "runtime_frames"
        case duration = "duration_seconds"
        case repeats = "loop"
        case returnTo = "return_to"
        case crossfadeIn = "crossfade_in_seconds"
        case crossfadeOut = "crossfade_out_seconds"
    }
}

/// 与模型一同交付的动画能力目录。
public struct MascotAnimationCatalog: Equatable, Sendable, Decodable {
    public let schema: String
    public let modelFilename: String
    public let framesPerSecond: Int
    public let usesRootMotion: Bool
    public let defaultAnimation: MascotAnimationID
    public let animations: [MascotAnimationID: MascotAnimationClip]
    public let eventBindings: [MascotEventID: MascotAnimationID]

    enum CodingKeys: String, CodingKey {
        case schema
        case modelFilename = "asset"
        case framesPerSecond = "fps"
        case usesRootMotion = "root_motion"
        case defaultAnimation = "default_clip"
        case animations = "clips"
        case eventBindings = "suggested_events"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schema = try container.decode(String.self, forKey: .schema)
        modelFilename = try container.decode(String.self, forKey: .modelFilename)
        framesPerSecond = try container.decode(Int.self, forKey: .framesPerSecond)
        usesRootMotion = try container.decode(Bool.self, forKey: .usesRootMotion)
        defaultAnimation = MascotAnimationID(
            rawValue: try container.decode(String.self, forKey: .defaultAnimation)
        )

        let rawAnimations = try container.decode(
            [String: MascotAnimationClip].self,
            forKey: .animations
        )
        animations = Dictionary(
            uniqueKeysWithValues: rawAnimations.map {
                (MascotAnimationID(rawValue: $0.key), $0.value)
            }
        )

        let rawBindings = try container.decodeIfPresent(
            [String: String].self,
            forKey: .eventBindings
        ) ?? [:]
        eventBindings = Dictionary(
            uniqueKeysWithValues: rawBindings.map {
                (MascotEventID(rawValue: $0.key), MascotAnimationID(rawValue: $0.value))
            }
        )
    }

    public func animation(for semantic: MascotAnimationSemantic) -> MascotAnimationID? {
        animations.first(where: { $0.value.semantic == semantic })?.key
    }

    public func animation(for event: MascotEventID) -> MascotAnimationID? {
        eventBindings[event]
    }

    public func clip(_ id: MascotAnimationID) -> MascotAnimationClip? {
        animations[id]
    }

    /// 在模型进入渲染层之前验证资产契约，尽早暴露不完整的交付包。
    public func validate() throws {
        guard schema == "gugu_animation_map.v1" else {
            throw MascotResourceError.unsupportedSchema(schema)
        }
        guard framesPerSecond > 0 else {
            throw MascotResourceError.invalidCatalog("fps 必须大于 0")
        }
        guard animations[defaultAnimation] != nil else {
            throw MascotResourceError.invalidCatalog("默认动画不存在：\(defaultAnimation.rawValue)")
        }

        for (id, clip) in animations {
            guard clip.duration > 0 else {
                throw MascotResourceError.invalidCatalog("动画时长必须大于 0：\(id.rawValue)")
            }
            guard clip.runtimeFrames.lowerBound <= clip.runtimeFrames.upperBound else {
                throw MascotResourceError.invalidCatalog("运行时帧区间无效：\(id.rawValue)")
            }
            if let returnTo = clip.returnTo, animations[returnTo] == nil {
                throw MascotResourceError.invalidCatalog(
                    "动画 \(id.rawValue) 的回落动作不存在：\(returnTo.rawValue)"
                )
            }
        }

        for (event, animation) in eventBindings where animations[animation] == nil {
            throw MascotResourceError.invalidCatalog(
                "事件 \(event.rawValue) 指向不存在的动画：\(animation.rawValue)"
            )
        }
    }
}

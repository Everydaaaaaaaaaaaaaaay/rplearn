import Foundation

/// 随消息落库的来源。字数和正确率均由服务端决定。
public enum LearningChatOrigin: Sendable, Equatable, Codable {
    case user(cycleID: UUID)
    case assistant(cycleID: UUID, userMessageID: UUID, operationID: UUID, fragmentIndex: Int, fragmentCount: Int)

    public var cycleID: UUID {
        switch self {
        case .user(let cycleID), .assistant(let cycleID, _, _, _, _): cycleID
        }
    }

    private enum CodingKeys: String, CodingKey {
        case source, cycleId, userMessageId, operationId, fragmentIndex, fragmentCount
    }
    public init(from decoder: Decoder) throws {
        let value = try decoder.container(keyedBy: CodingKeys.self)
        let cycle = try value.decode(UUID.self, forKey: .cycleId)
        switch try value.decode(String.self, forKey: .source) {
        case "user": self = .user(cycleID: cycle)
        case "assistant":
            let index = try value.decode(Int.self, forKey: .fragmentIndex)
            let count = try value.decode(Int.self, forKey: .fragmentCount)
            guard (1...8).contains(count), (0..<count).contains(index) else {
                throw DecodingError.dataCorruptedError(forKey: .fragmentIndex, in: value, debugDescription: "回复分片位置不合法。")
            }
            self = .assistant(cycleID: cycle,
                userMessageID: try value.decode(UUID.self, forKey: .userMessageId),
                operationID: try value.decode(UUID.self, forKey: .operationId),
                fragmentIndex: index, fragmentCount: count)
        default:
            throw DecodingError.dataCorruptedError(forKey: .source, in: value, debugDescription: "无法识别消息的学习来源。")
        }
    }
    public func encode(to encoder: Encoder) throws {
        var value = encoder.container(keyedBy: CodingKeys.self)
        try value.encode(cycleID.uuidString.lowercased(), forKey: .cycleId)
        switch self {
        case .user:
            try value.encode("user", forKey: .source)
        case .assistant(_, let user, let operation, let index, let count):
            guard (1...8).contains(count), (0..<count).contains(index) else {
                throw EncodingError.invalidValue(self, .init(codingPath: encoder.codingPath, debugDescription: "回复分片位置不合法。"))
            }
            try value.encode("assistant", forKey: .source)
            try value.encode(user.uuidString.lowercased(), forKey: .userMessageId)
            try value.encode(operation.uuidString.lowercased(), forKey: .operationId)
            try value.encode(index, forKey: .fragmentIndex)
            try value.encode(count, forKey: .fragmentCount)
        }
    }
    public func encodedJSON() throws -> String {
        String(decoding: try JSONEncoder().encode(self), as: UTF8.self)
    }
    public static func decode(json: String?) -> Self? {
        guard let json else { return nil }
        return try? JSONDecoder().decode(Self.self, from: Data(json.utf8))
    }
}

/// 模型请求引用已保存的用户消息，周期不随请求重试而改变。
public struct LearningChatContext: Sendable, Equatable, Codable {
    public let conversationId: UUID
    public let userMessageId: UUID
    public let cycleId: UUID
    public init(conversationID: UUID, userMessageID: UUID, cycleID: UUID) {
        conversationId = conversationID; userMessageId = userMessageID; cycleId = cycleID
    }
    public func assistantOrigin(operationID: UUID, index: Int, count: Int) -> LearningChatOrigin {
        .assistant(cycleID: cycleId, userMessageID: userMessageId, operationID: operationID,
                   fragmentIndex: index, fragmentCount: count)
    }
}

public struct LearningReplySource: Sendable, Equatable {
    public let context: LearningChatContext
    public let operationID: UUID
    public init(context: LearningChatContext, operationID: UUID) {
        self.context = context; self.operationID = operationID
    }
    public func origin(index: Int, count: Int) -> LearningChatOrigin {
        context.assistantOrigin(operationID: operationID, index: index, count: count)
    }
}

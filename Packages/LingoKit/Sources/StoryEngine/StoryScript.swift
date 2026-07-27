import Foundation

/// 剧情脚本 JSON DSL。
/// 节点类型：line（台词）/ choice（选项）/ branch（按 flag 分支）/ reward（奖励）/ end（结束）。
public struct StoryScript: Sendable, Equatable {
    public var id: String
    public var start: String
    public var nodes: [String: StoryNode]

    public init(id: String, start: String, nodes: [StoryNode]) throws {
        self.id = id
        self.start = start
        self.nodes = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        try validate()
    }

    public static func load(from url: URL) throws -> StoryScript {
        let data = try Data(contentsOf: url)
        return try load(from: data)
    }

    public static func load(from data: Data) throws -> StoryScript {
        let file = try JSONDecoder().decode(File.self, from: data)
        return try StoryScript(id: file.id, start: file.start, nodes: file.nodes)
    }

    public func node(_ id: String) -> StoryNode? {
        nodes[id]
    }

    // MARK: - 静态校验：引用齐全 + 全部可达（加载即失败，避免运行期悬空）

    public enum ValidationError: Error, Equatable {
        case missingStart(String)
        case danglingReference(from: String, to: String)
        case unreachableNodes([String])
        case emptyChoice(String)
    }

    private func validate() throws {
        guard nodes[start] != nil else {
            throw ValidationError.missingStart(start)
        }
        for node in nodes.values {
            for target in node.referencedNodeIDs {
                guard nodes[target] != nil else {
                    throw ValidationError.danglingReference(from: node.id, to: target)
                }
            }
            if case .choice(let options) = node.payload, options.isEmpty {
                throw ValidationError.emptyChoice(node.id)
            }
        }
        // BFS 可达性
        var visited: Set<String> = []
        var queue = [start]
        while let current = queue.popLast() {
            guard visited.insert(current).inserted, let node = nodes[current] else { continue }
            queue.append(contentsOf: node.referencedNodeIDs)
        }
        let unreachable = Set(nodes.keys).subtracting(visited)
        guard unreachable.isEmpty else {
            throw ValidationError.unreachableNodes(unreachable.sorted())
        }
    }

    private struct File: Decodable {
        let id: String
        let start: String
        let nodes: [StoryNode]
    }
}

/// 剧情奖励。
public struct StoryReward: Sendable, Equatable {
    public var coins: Int
    /// nil = 无机票；"universal" 或国家码（如 "GB"）。
    public var ticket: String?

    public init(coins: Int = 0, ticket: String? = nil) {
        self.coins = coins
        self.ticket = ticket
    }
}

public struct StoryChoiceOption: Sendable, Equatable, Decodable {
    public var text: String
    public var next: String
    public var setFlags: [String: Bool]?
}

public struct StoryNode: Sendable, Equatable, Identifiable, Decodable {
    public enum Payload: Sendable, Equatable {
        /// 台词。bg/sprite 缺省沿用上一节点（AVG 皮肤用；聊天皮肤忽略）。
        case line(speaker: String, text: String, bg: String?, sprite: String?, next: String)
        case choice(options: [StoryChoiceOption])
        case branch(flag: String, ifTrue: String, ifFalse: String)
        case reward(StoryReward, next: String)
        case end(unlocks: [String])
    }

    public var id: String
    public var payload: Payload

    /// 该节点引用到的所有节点 id（校验用）。
    var referencedNodeIDs: [String] {
        switch payload {
        case .line(_, _, _, _, let next): [next]
        case .choice(let options): options.map(\.next)
        case .branch(_, let ifTrue, let ifFalse): [ifTrue, ifFalse]
        case .reward(_, let next): [next]
        case .end: []
        }
    }

    // MARK: - Decodable（type 字段判别）

    private enum CodingKeys: String, CodingKey {
        case id, type, speaker, text, bg, sprite, next, options, flag, ifTrue, ifFalse, coins, ticket, unlocks
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "line":
            payload = .line(
                speaker: try container.decode(String.self, forKey: .speaker),
                text: try container.decode(String.self, forKey: .text),
                bg: try container.decodeIfPresent(String.self, forKey: .bg),
                sprite: try container.decodeIfPresent(String.self, forKey: .sprite),
                next: try container.decode(String.self, forKey: .next)
            )
        case "choice":
            payload = .choice(options: try container.decode([StoryChoiceOption].self, forKey: .options))
        case "branch":
            payload = .branch(
                flag: try container.decode(String.self, forKey: .flag),
                ifTrue: try container.decode(String.self, forKey: .ifTrue),
                ifFalse: try container.decode(String.self, forKey: .ifFalse)
            )
        case "reward":
            payload = .reward(
                StoryReward(
                    coins: try container.decodeIfPresent(Int.self, forKey: .coins) ?? 0,
                    ticket: try container.decodeIfPresent(String.self, forKey: .ticket)
                ),
                next: try container.decode(String.self, forKey: .next)
            )
        case "end":
            payload = .end(unlocks: try container.decodeIfPresent([String].self, forKey: .unlocks) ?? [])
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "未知节点类型: \(type)"
            )
        }
    }

    public init(id: String, payload: Payload) {
        self.id = id
        self.payload = payload
    }
}

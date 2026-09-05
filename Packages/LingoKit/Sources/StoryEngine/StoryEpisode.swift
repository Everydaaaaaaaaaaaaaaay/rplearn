import Foundation

/// Versioned, pre-authored visual-novel episode. Each shot is a full scene snapshot;
/// no inherited rendering state is required to resume a checkpoint.
public struct StoryEpisode: Decodable, Sendable {
    public struct Actor: Decodable, Sendable, Equatable {
        public let id: String
        public let asset: String
        public let x: Double
        public let scale: Double
    }
    public struct Shot: Decodable, Sendable, Equatable {
        public let background: String
        public let actors: [Actor]
    }
    public struct Choice: Decodable, Sendable, Identifiable {
        public let id: String
        public let text: String
        public let translation: String
        public let next: String
        public let flags: [String: Bool]
    }
    public struct Branch: Decodable, Sendable {
        public let flag: String
        public let yes: String
        public let no: String
    }
    public struct Node: Decodable, Sendable, Identifiable {
        public let id: String
        public let act: Int
        public let location: String
        public let shot: String
        public let speaker: String
        public let text: String
        public let translation: String
        public let next: String?
        public let choices: [Choice]?
        public let branch: Branch?
        public let ending: Bool?

        public var targets: [String] {
            if let choices { return choices.map(\.next) }
            if let branch { return [branch.yes, branch.no] }
            return next.map { [$0] } ?? []
        }
    }

    public let id: String
    public let version: Int
    public let title: String
    public let start: String
    public let acts: [String]
    public let shots: [String: Shot]
    public let nodes: [Node]

    public enum ValidationError: Error, Equatable {
        case invalid(String)
    }

    public static func load(data: Data) throws -> Self {
        let episode = try JSONDecoder().decode(Self.self, from: data)
        try episode.validate()
        return episode
    }

    public var assetNames: Set<String> {
        Set(shots.values.flatMap { [$0.background] + $0.actors.map(\.asset) })
    }

    public func node(_ id: String) -> Node? { nodes.first { $0.id == id } }

    public func validate() throws {
        func reject(_ message: String) throws { throw ValidationError.invalid(message) }
        guard version > 0, !id.isEmpty, !acts.isEmpty else { return try reject("metadata") }
        let ids = Set(nodes.map(\.id))
        guard ids.count == nodes.count, ids.contains(start) else { return try reject("node IDs/start") }
        for shot in shots.values {
            guard !shot.background.isEmpty,
                  Set(shot.actors.map(\.id)).count == shot.actors.count,
                  shot.actors.allSatisfy({ !$0.asset.isEmpty && (0...1).contains($0.x) && (0.1...1.5).contains($0.scale) })
            else { return try reject("shot") }
        }
        for node in nodes {
            let exits = (node.next == nil ? 0 : 1) + (node.choices == nil ? 0 : 1)
                + (node.branch == nil ? 0 : 1) + (node.ending == true ? 1 : 0)
            guard exits == 1, shots[node.shot] != nil, acts.indices.contains(node.act),
                  !node.text.isEmpty, !node.translation.isEmpty,
                  node.targets.allSatisfy({ ids.contains($0) }) else { return try reject(node.id) }
            if let choices = node.choices {
                guard choices.count >= 2, Set(choices.map(\.id)).count == choices.count,
                      choices.allSatisfy({ !$0.text.isEmpty && !$0.translation.isEmpty })
                else { return try reject("choices: \(node.id)") }
            }
        }
        // This pilot deliberately has no loops: every route must reach an ending.
        var visiting = Set<String>()
        var visited = Set<String>()
        func visit(_ id: String) throws {
            if visiting.contains(id) { return try reject("cycle: \(id)") }
            if visited.contains(id) { return }
            visiting.insert(id)
            for target in node(id)!.targets { try visit(target) }
            visiting.remove(id)
            visited.insert(id)
        }
        try visit(start)
        guard visited == ids else { return try reject("unreachable") }
    }
}

/// Pilot-only local checkpoint. Stores decisions, then replays the validated graph
/// to restore flags/history. Malformed or stale checkpoints restart safely.
public struct EpisodeSession: Sendable {
    public struct Checkpoint: Codable, Sendable, Equatable {
        public let episodeID: String
        public let version: Int
        public let nodeID: String
        public let decisions: [String: String]
    }
    public let episode: StoryEpisode
    public private(set) var nodeID: String
    public private(set) var flags: [String: Bool] = [:]
    public private(set) var decisions: [String: String] = [:]
    public private(set) var history: [String] = []

    public var current: StoryEpisode.Node { episode.node(nodeID)! }
    public var shot: StoryEpisode.Shot { episode.shots[current.shot]! }
    public var isFinished: Bool { current.ending == true }
    public var checkpoint: Checkpoint {
        Checkpoint(episodeID: episode.id, version: episode.version, nodeID: nodeID, decisions: decisions)
    }

    public init(episode: StoryEpisode, saved: Data? = nil) {
        self.episode = episode
        self.nodeID = episode.start
        guard let saved, let cp = try? JSONDecoder().decode(Checkpoint.self, from: saved),
              cp.episodeID == episode.id, cp.version == episode.version else { return }
        var restored = self
        for _ in 0..<episode.nodes.count {
            if restored.nodeID == cp.nodeID {
                if restored.decisions == cp.decisions {
                    nodeID = restored.nodeID
                    flags = restored.flags
                    decisions = restored.decisions
                    history = restored.history
                }
                return
            }
            if let choices = restored.current.choices {
                guard let choiceID = cp.decisions[restored.nodeID],
                      choices.contains(where: { $0.id == choiceID }) else { return }
                restored.choose(choiceID)
            } else if !restored.advance() { return }
        }
    }

    @discardableResult public mutating func advance() -> Bool {
        guard current.choices == nil, !isFinished else { return false }
        let next: String?
        if let branch = current.branch { next = flags[branch.flag] == true ? branch.yes : branch.no }
        else { next = current.next }
        guard let next else { return false }
        history.append(nodeID)
        nodeID = next
        return true
    }

    public mutating func choose(_ id: String) {
        guard let choice = current.choices?.first(where: { $0.id == id }) else { return }
        decisions[nodeID] = id
        flags.merge(choice.flags) { _, new in new }
        history.append(nodeID)
        nodeID = choice.next
    }
}

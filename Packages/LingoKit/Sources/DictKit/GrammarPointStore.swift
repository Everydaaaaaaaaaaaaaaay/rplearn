import Foundation

/// 手工语法点。trigger 词命中时与词典释义并列展示；related 支持点击跳转。
public struct GrammarPoint: Sendable, Codable, Equatable, Identifiable {
    public struct Example: Sendable, Codable, Equatable {
        public var en: String
        public var zh: String
    }

    public var id: String
    /// 触发该语法点的单词（小写），如 ["as"]。
    public var triggers: [String]
    public var title: String
    public var explanationZh: String
    public var examples: [Example]
    /// 相关语法点 id，可跳转。
    public var related: [String]
}

public struct GrammarPointStore: Sendable {
    private let pointsByTrigger: [String: [GrammarPoint]]
    private let pointsByID: [String: GrammarPoint]
    public let allPoints: [GrammarPoint]

    public init(url: URL) throws {
        struct File: Decodable {
            let points: [GrammarPoint]
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let file = try decoder.decode(File.self, from: Data(contentsOf: url))
        self.init(points: file.points)
    }

    public init(points: [GrammarPoint]) {
        allPoints = points
        var byTrigger: [String: [GrammarPoint]] = [:]
        var byID: [String: GrammarPoint] = [:]
        for point in points {
            byID[point.id] = point
            for trigger in point.triggers {
                byTrigger[trigger.lowercased(), default: []].append(point)
            }
        }
        pointsByTrigger = byTrigger
        pointsByID = byID
    }

    public func points(forTrigger word: String) -> [GrammarPoint] {
        pointsByTrigger[word.lowercased()] ?? []
    }

    public func point(id: String) -> GrammarPoint? {
        pointsByID[id]
    }
}

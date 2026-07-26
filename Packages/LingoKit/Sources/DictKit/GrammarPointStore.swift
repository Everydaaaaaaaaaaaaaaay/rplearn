import CoreKit
import Foundation

/// 一条可在自然对话中识别的有序语法模式。
///
/// `steps` 中每个字符串代表一个词位，使用 `|` 表示可选词形；
/// `<word>` 与 `<gerund>` 分别匹配任意单词和动名词。
/// `maximumGaps` 表示相邻词位之间最多允许跳过的单词数。
public struct GrammarPattern: Sendable, Codable, Equatable {
    public var steps: [String]
    public var maximumGaps: [Int]
    public var highlightedSteps: [Int]?
}

/// 手工语法点。trigger 用于单词卡关联，patterns 用于对话内结构检测。
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
    /// 需要完整命中后才会在角色消息中高亮的语法结构。
    public var patterns: [GrammarPattern]?
}

/// 一次完整语法结构命中；只暴露应该着色和交互的 token。
public struct GrammarMatch: Sendable, Equatable {
    public var pointID: String
    public var tokenIDs: [Int]
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

    /// 在一段已分词文本中查找完整语法结构。
    ///
    /// 更具体（词位更多）的模式优先，避免 `so that + 情态动词` 同时被识别为
    /// 目的结构和普通的 `so ... that ...` 结果结构。
    public func matches(in tokens: [TextToken]) -> [GrammarMatch] {
        let words = tokens.compactMap { token -> WordToken? in
            guard let word = token.word else { return nil }
            return WordToken(tokenID: token.id, word: word)
        }
        guard !words.isEmpty else { return [] }

        var candidates: [Candidate] = []
        for (pointOrder, point) in allPoints.enumerated() {
            for pattern in point.patterns ?? [] where !pattern.steps.isEmpty {
                for positions in Self.matchPositions(
                    pattern: pattern,
                    words: words,
                    tokens: tokens
                ) {
                    let highlightedSteps = pattern.highlightedSteps
                        ?? Array(pattern.steps.indices)
                    let tokenIDs = highlightedSteps.compactMap { stepIndex in
                        positions.indices.contains(stepIndex)
                            ? words[positions[stepIndex]].tokenID
                            : nil
                    }
                    guard !tokenIDs.isEmpty else { continue }
                    candidates.append(
                        Candidate(
                            pointID: point.id,
                            tokenIDs: tokenIDs,
                            stepCount: pattern.steps.count,
                            span: positions.last.map { $0 - positions[0] } ?? 0,
                            pointOrder: pointOrder
                        )
                    )
                }
            }
        }

        candidates.sort {
            if $0.stepCount != $1.stepCount {
                return $0.stepCount > $1.stepCount
            }
            if $0.span != $1.span {
                return $0.span < $1.span
            }
            if $0.pointOrder != $1.pointOrder {
                return $0.pointOrder < $1.pointOrder
            }
            return ($0.tokenIDs.first ?? 0) < ($1.tokenIDs.first ?? 0)
        }

        var occupiedTokenIDs: Set<Int> = []
        var accepted: [GrammarMatch] = []
        for candidate in candidates {
            guard occupiedTokenIDs.isDisjoint(with: candidate.tokenIDs) else { continue }
            occupiedTokenIDs.formUnion(candidate.tokenIDs)
            accepted.append(
                GrammarMatch(pointID: candidate.pointID, tokenIDs: candidate.tokenIDs)
            )
        }
        return accepted.sorted {
            ($0.tokenIDs.first ?? 0) < ($1.tokenIDs.first ?? 0)
        }
    }

    /// 供逐词 UI 直接消费的 token → 语法点映射。
    public func annotations(in tokens: [TextToken]) -> [Int: String] {
        var result: [Int: String] = [:]
        for match in matches(in: tokens) {
            for tokenID in match.tokenIDs {
                result[tokenID] = match.pointID
            }
        }
        return result
    }

    private struct WordToken {
        let tokenID: Int
        let word: String
    }

    private struct Candidate {
        let pointID: String
        let tokenIDs: [Int]
        let stepCount: Int
        let span: Int
        let pointOrder: Int
    }

    private static func matchPositions(
        pattern: GrammarPattern,
        words: [WordToken],
        tokens: [TextToken]
    ) -> [[Int]] {
        var results: [[Int]] = []

        func search(stepIndex: Int, positions: [Int]) {
            guard stepIndex < pattern.steps.count else {
                results.append(positions)
                return
            }

            let lowerBound: Int
            let upperBound: Int
            if let previous = positions.last {
                let maximumGap = pattern.maximumGaps.indices.contains(stepIndex - 1)
                    ? max(0, pattern.maximumGaps[stepIndex - 1])
                    : 0
                lowerBound = previous + 1
                upperBound = min(words.count - 1, previous + maximumGap + 1)
            } else {
                lowerBound = 0
                upperBound = words.count - 1
            }
            guard lowerBound <= upperBound else { return }

            for position in lowerBound...upperBound {
                if let previous = positions.last,
                   crossesSentenceBoundary(
                       fromTokenID: words[previous].tokenID,
                       toTokenID: words[position].tokenID,
                       tokens: tokens
                   ) {
                    break
                }
                guard matches(words[position].word, expression: pattern.steps[stepIndex]) else {
                    continue
                }
                search(stepIndex: stepIndex + 1, positions: positions + [position])
            }
        }

        search(stepIndex: 0, positions: [])
        return results
    }

    private static func matches(_ word: String, expression: String) -> Bool {
        expression
            .lowercased()
            .split(separator: "|")
            .contains { option in
                switch option {
                case "<word>":
                    return true
                case "<gerund>":
                    return word.count > 4 && word.hasSuffix("ing")
                default:
                    return word == option
                }
            }
    }

    private static func crossesSentenceBoundary(
        fromTokenID: Int,
        toTokenID: Int,
        tokens: [TextToken]
    ) -> Bool {
        guard fromTokenID < toTokenID else { return false }
        let boundaryCharacters = CharacterSet(charactersIn: ".!?;\n")
        return tokens[fromTokenID..<toTokenID].contains { token in
            token.display.rangeOfCharacter(from: boundaryCharacters) != nil
        }
    }
}

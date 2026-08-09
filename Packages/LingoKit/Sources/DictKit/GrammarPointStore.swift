import CoreKit
import Foundation

/// 一条可在自然对话中识别的有序语法模式。
///
/// `steps` 中每个字符串代表一个词位，使用 `|` 表示可选词形；
/// `<word>`、`<gerund>`、`<past-participle>` 与 `<comparative>` 提供有限的词形匹配。
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
    /// 更具体的结构命中时可压制的泛化语法点，避免同一用法重复解释。
    public var supersedes: [String]?
}

/// 一次完整语法结构命中；只暴露应该着色和交互的 token。
public struct GrammarMatch: Sendable, Equatable {
    public var pointID: String
    /// 应在句子中强调、可交互的结构词。
    public var tokenIDs: [Int]
    /// 从首个匹配词到末个匹配词的完整 token 范围，供整句解析展示原文片段。
    public var spanTokenIDs: [Int]
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
        let sentenceBoundaryPrefix = Self.sentenceBoundaryPrefix(in: tokens)

        var candidates: [Candidate] = []
        for (pointOrder, point) in allPoints.enumerated() {
            for pattern in point.patterns ?? [] where !pattern.steps.isEmpty {
                for positions in Self.matchPositions(
                    pattern: pattern,
                    words: words,
                    sentenceBoundaryPrefix: sentenceBoundaryPrefix
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
                            spanTokenIDs: Array(
                                words[positions[0]].tokenID...words[positions[positions.count - 1]].tokenID
                            ),
                            supersedes: Set(point.supersedes ?? []),
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

        var acceptedSignatures: Set<[Int]> = []
        var supersededPointIDs: Set<String> = []
        var accepted: [GrammarMatch] = []
        for candidate in candidates {
            // 完全相同的结构词由更具体的模式优先；部分重叠仍保留，
            // 例如一句话可同时包含现在完成时和 have been to 结构。
            guard acceptedSignatures.insert(candidate.tokenIDs).inserted,
                  !supersededPointIDs.contains(candidate.pointID)
            else { continue }
            accepted.append(
                GrammarMatch(
                    pointID: candidate.pointID,
                    tokenIDs: candidate.tokenIDs,
                    spanTokenIDs: candidate.spanTokenIDs
                )
            )
            supersededPointIDs.formUnion(candidate.supersedes)
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
        let grammaticalForms: Set<String>
        let isGerund: Bool
        let isPastParticiple: Bool
        let isComparative: Bool

        init(tokenID: Int, word: String) {
            let normalizedWord = word.replacingOccurrences(of: "’", with: "'")
            self.tokenID = tokenID
            grammaticalForms = GrammarPointStore.grammaticalForms(for: normalizedWord)
            isGerund = normalizedWord.count > 4 && normalizedWord.hasSuffix("ing")
            isPastParticiple = GrammarPointStore.isLikelyPastParticiple(normalizedWord)
            isComparative = GrammarPointStore.isLikelyComparative(normalizedWord)
        }
    }

    private enum PatternOption {
        case anyWord
        case gerund
        case pastParticiple
        case comparative
        case literal(String)
    }

    private struct Candidate {
        let pointID: String
        let tokenIDs: [Int]
        let spanTokenIDs: [Int]
        let supersedes: Set<String>
        let stepCount: Int
        let span: Int
        let pointOrder: Int
    }

    private static func matchPositions(
        pattern: GrammarPattern,
        words: [WordToken],
        sentenceBoundaryPrefix: [Int]
    ) -> [[Int]] {
        var results: [[Int]] = []
        var positions: [Int] = []
        positions.reserveCapacity(pattern.steps.count)
        let expressions = pattern.steps.map(parseExpression)

        func search(stepIndex: Int) {
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
                       sentenceBoundaryPrefix: sentenceBoundaryPrefix
                   ) {
                    break
                }
                guard matches(words[position], options: expressions[stepIndex]) else {
                    continue
                }
                positions.append(position)
                search(stepIndex: stepIndex + 1)
                positions.removeLast()
            }
        }

        search(stepIndex: 0)
        return results
    }

    private static func parseExpression(_ expression: String) -> [PatternOption] {
        expression
            .lowercased()
            .split(separator: "|")
            .map { option in
                switch option {
                case "<word>":
                    return .anyWord
                case "<gerund>":
                    return .gerund
                case "<past-participle>":
                    return .pastParticiple
                case "<comparative>":
                    return .comparative
                default:
                    return .literal(String(option))
                }
            }
    }

    private static func matches(_ word: WordToken, options: [PatternOption]) -> Bool {
        options.contains { option in
            switch option {
            case .anyWord:
                true
            case .gerund:
                word.isGerund
            case .pastParticiple:
                word.isPastParticiple
            case .comparative:
                word.isComparative
            case let .literal(value):
                word.grammaticalForms.contains(value)
            }
        }
    }

    /// 一个聊天 token 可能同时包含主语和缩写助动词；保留原词并补充可能的助动词形式，
    /// 后续结构词会自然消除 `'s`（is / has）、`'d`（had / would）等歧义。
    private static func grammaticalForms(for word: String) -> Set<String> {
        var forms: Set<String> = [word]
        if word.hasSuffix("'m") { forms.insert("am") }
        if word.hasSuffix("'re") { forms.insert("are") }
        if word.hasSuffix("'ve") { forms.insert("have") }
        if word.hasSuffix("'ll") { forms.insert("will") }
        if word.hasSuffix("'d") {
            forms.formUnion(["had", "would"])
        }
        if word.hasSuffix("'s") {
            forms.formUnion(["is", "has"])
        }
        let negativeAuxiliaries: [String: String] = [
            "aren't": "are", "can't": "can", "couldn't": "could", "didn't": "did",
            "doesn't": "does", "don't": "do", "hadn't": "had", "hasn't": "has",
            "haven't": "have", "isn't": "is", "mightn't": "might", "mustn't": "must",
            "shouldn't": "should", "wasn't": "was", "weren't": "were", "won't": "will",
            "wouldn't": "would",
        ]
        if let auxiliary = negativeAuxiliaries[word] {
            forms.insert(auxiliary)
        }
        return forms
    }

    private static func isLikelyPastParticiple(_ word: String) -> Bool {
        if word.count > 3, word.hasSuffix("ed") || word.hasSuffix("en") {
            return true
        }
        return irregularPastParticiples.contains(word)
    }

    private static func isLikelyComparative(_ word: String) -> Bool {
        commonComparatives.contains(word) || (word.count > 4 && word.hasSuffix("ier"))
    }

    private static let irregularPastParticiples: Set<String> = [
        "been", "become", "begun", "bent", "bet", "bitten", "blown", "broken", "brought",
        "built", "bought", "caught", "chosen", "come", "cost", "cut", "dealt", "done",
        "drawn", "driven", "drunk", "eaten", "fallen", "fed", "felt", "fought", "found",
        "flown", "forgotten", "forgiven", "frozen", "given", "gone", "got", "gotten",
        "grown", "had", "heard", "held", "hidden", "hit", "kept", "known", "laid", "led",
        "left", "lent", "lost", "made", "meant", "met", "paid", "put", "read", "ridden",
        "risen", "run", "said", "seen", "sold", "sent", "set", "shown", "shut", "sung",
        "sat", "slept", "spoken", "spent", "stood", "stolen", "swum", "taken", "taught",
        "thought", "thrown", "told", "understood", "woken", "worn", "won", "written",
    ]

    private static let commonComparatives: Set<String> = [
        "better", "bigger", "cheaper", "cleaner", "closer", "colder", "cooler", "darker",
        "earlier", "easier", "farther", "faster", "fewer", "further", "greater", "harder",
        "healthier", "higher", "hotter", "larger", "later", "less", "lighter", "longer",
        "louder", "lower", "more", "nearer", "newer", "nicer", "older", "quicker", "safer",
        "shorter", "simpler", "slower", "smaller", "sooner", "stronger", "taller", "warmer",
        "weaker", "wider", "worse", "younger",
    ]

    private static func crossesSentenceBoundary(
        fromTokenID: Int,
        toTokenID: Int,
        sentenceBoundaryPrefix: [Int]
    ) -> Bool {
        guard fromTokenID < toTokenID else { return false }
        guard sentenceBoundaryPrefix.indices.contains(fromTokenID),
              sentenceBoundaryPrefix.indices.contains(toTokenID)
        else { return true }
        return sentenceBoundaryPrefix[toTokenID] > sentenceBoundaryPrefix[fromTokenID]
    }

    private static func sentenceBoundaryPrefix(in tokens: [TextToken]) -> [Int] {
        let boundaryCharacters = CharacterSet(charactersIn: ".!?;\n")
        var prefix = [Int](repeating: 0, count: tokens.count + 1)
        for (index, token) in tokens.enumerated() {
            prefix[index + 1] = prefix[index]
                + (token.display.rangeOfCharacter(from: boundaryCharacters) == nil ? 0 : 1)
        }
        return prefix
    }
}

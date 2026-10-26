import BackendKit

enum LearningHistoryAccuracyFilter: String, CaseIterable, Identifiable {
    case all, high, medium, low

    var id: Self { self }
    var title: String {
        switch self {
        case .all: "全部正确率"
        case .high: "绿色 · 答对 ≥70%"
        case .medium: "黄色 · 答对 50%–不足70%"
        case .low: "红色 · 答对 <50%"
        }
    }
    var summary: String {
        switch self {
        case .all: ""
        case .high: "≥70%"
        case .medium: "50%–<70%"
        case .low: "<50%"
        }
    }
    func matches(correct: Int, total: Int) -> Bool {
        let band = LearningAccuracyBand(correct: correct, total: total)
        switch self {
        case .all: return true
        case .high: return band == .high
        case .medium: return band == .medium
        case .low: return band == .low
        }
    }
}

struct LearningHistoryFilter: Equatable {
    var onlyUnfinished = false
    var accuracy = LearningHistoryAccuracyFilter.all

    var isActive: Bool { onlyUnfinished || accuracy != .all }
    var summary: String {
        [onlyUnfinished ? "待补答" : "", accuracy.summary].filter { !$0.isEmpty }.joined(separator: " · ")
    }
    func matches(_ item: LearningHistory.Item) -> Bool {
        (!onlyUnfinished || (item.firstCompletedAt != nil && item.correctCount < item.questionCount))
            && accuracy.matches(correct: item.correctCount, total: item.questionCount)
    }
}

/// Whole percentages never show 100% until the actual unlock threshold is reached.
func learningChatPercentage(characters: Int, threshold: Int) -> Int {
    guard threshold > 0 else { return 0 }
    guard characters < threshold else { return 100 }
    return Int((Double(max(0, characters)) * 100 / Double(threshold)).rounded(.down))
}

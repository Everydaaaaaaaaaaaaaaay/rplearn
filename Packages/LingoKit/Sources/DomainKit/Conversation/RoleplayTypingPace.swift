import Foundation

/// Local evidence of composing. Four distinct newly added characters extend the wait; focus never does.
public struct RoleplayComposerActivity: Sendable {
    public private(set) var isFocused = false
    public private(set) var editedAt: Date?
    public private(set) var unfocusedAt: Date?

    private var lastQualifiedDraft = ""

    public init() {}

    public mutating func focusChanged(_ focused: Bool, at date: Date) {
        guard focused != isFocused else { return }
        isFocused = focused
        if !focused { unfocusedAt = date }
    }

    public mutating func recordEdit(from oldDraft: String, to newDraft: String, at date: Date) {
        let current = Array(newDraft.lowercased())
        // Deletion, cursor movement and capitalization alone cannot renew the lease.
        let insertedThisEdit = current.difference(from: Array(oldDraft.lowercased())).contains {
            if case .insert = $0 { return true }
            return false
        }
        guard insertedThisEdit else { return }
        // Re-evaluate surviving additions, so typing and deleting noise cannot accumulate
        // credit, and an already-qualified draft cannot renew on every subsequent keystroke.
        let additions = current.difference(from: Array(lastQualifiedDraft)).compactMap { change -> Character? in
            guard case let .insert(_, character, _) = change, !character.isWhitespace else { return nil }
            return character
        }
        guard Set(additions).count >= 4 else { return }
        editedAt = date
        lastQualifiedDraft = newDraft.lowercased()
    }

    /// Sending finishes this composition, even if the keyboard remains open.
    public mutating func didSend() {
        editedAt = nil
        unfocusedAt = nil
        lastQualifiedDraft = ""
    }
}

/// 文本聊天的回合交接策略。
///
/// 用户消息立即送达，但角色会等待一段安静时间再开始回复。短时间内连续发送的
/// 多条消息会自然合并成一个话轮；输入框仍有编辑活动时，等待会被续期。
public struct RoleplayTurnTakingPolicy: Sendable {
    public static let standard = RoleplayTurnTakingPolicy()

    public let minimumQuietWindow: TimeInterval
    public let maximumQuietWindow: TimeInterval
    public let draftActivityExtension: TimeInterval
    public let unfocusedGrace: TimeInterval

    public init(
        minimumQuietWindow: TimeInterval = 8,
        maximumQuietWindow: TimeInterval = 9,
        draftActivityExtension: TimeInterval = 25,
        unfocusedGrace: TimeInterval = 5
    ) {
        self.minimumQuietWindow = minimumQuietWindow
        self.maximumQuietWindow = maximumQuietWindow
        self.draftActivityExtension = draftActivityExtension
        self.unfocusedGrace = unfocusedGrace
    }

    /// 根据最后一条消息是否像说完、长度及连续消息数量，计算开始回复前的静默窗口。
    /// `variation` 用于注入 0...1 的稳定可测随机量。
    public func quietWindow(
        after text: String,
        consecutiveUserMessageCount: Int,
        variation: Double
    ) -> TimeInterval {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.split(whereSeparator: \.isWhitespace).count
        let burstCount = max(1, consecutiveUserMessageCount)
        let clampedVariation = min(max(variation, 0), 1)

        let readingTime = min(Double(words) * 0.045, 0.75)
        let burstGrace = min(Double(burstCount - 1) * 0.32, 0.96)
        let unfinishedGrace = looksLikeOpenThought(trimmed) ? 0.7 : 0
        let jitter = (clampedVariation - 0.5) * 0.5
        let target = 8 + readingTime + burstGrace + unfinishedGrace + jitter
        return min(max(target, minimumQuietWindow), maximumQuietWindow)
    }

    /// Rechecking this deadline cannot extend it: only a new edit event can.
    /// Leaving the field shortens any outstanding grace to at most five seconds.
    public func handoffDate(sentAt: Date, quietWindow: TimeInterval,
                            activity: RoleplayComposerActivity) -> Date {
        var until = sentAt.addingTimeInterval(quietWindow)
        if let editedAt = activity.editedAt, editedAt >= sentAt {
            until = max(until, editedAt.addingTimeInterval(draftActivityExtension))
        }
        // Reopening the keyboard must not undo a previous dismissal's shorter deadline.
        if let exitedAt = activity.unfocusedAt, exitedAt >= sentAt,
           activity.editedAt.map({ $0 <= exitedAt }) ?? true {
            until = min(until, exitedAt.addingTimeInterval(unfocusedGrace))
        }
        return until
    }

    private func looksLikeOpenThought(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }

        let closingCharacters = CharacterSet(charactersIn: "\"'”’)]}")
        let visibleEnd = text.trimmingCharacters(in: closingCharacters)
        guard let last = visibleEnd.last else { return false }

        if ",;:—-…".contains(last) {
            return true
        }
        if ".?!。？！".contains(last) {
            return false
        }

        let lastWord = visibleEnd
            .lowercased()
            .split { !$0.isLetter }
            .last
            .map(String.init)
        let connectingWords: Set<String> = [
            "and", "but", "because", "if", "or", "so", "then", "though", "when", "while"
        ]
        return lastWord.map(connectingWords.contains) ?? true
    }
}

/// 将已经生成好的角色回复按接近真人打字的节奏逐条送达。
///
/// 首条消息只会部分扣除模型已经用于思考和生成的时间，并保留最低可感知输入时间；
/// 后续消息各自保留输入时间和换气停顿，让连续气泡不会机械地同时出现。
public struct RoleplayTypingPace: Sendable {
    public static let standard = RoleplayTypingPace()

    public let minimumDelay: TimeInterval
    public let maximumDelay: TimeInterval
    public let minimumFirstMessageDelay: TimeInterval

    public init(
        minimumDelay: TimeInterval = 1.2,
        maximumDelay: TimeInterval = 24,
        minimumFirstMessageDelay: TimeInterval = 1
    ) {
        self.minimumDelay = minimumDelay
        self.maximumDelay = maximumDelay
        self.minimumFirstMessageDelay = minimumFirstMessageDelay
    }

    /// - Parameters:
    ///   - messageIndex: 同一次角色回复中的气泡序号，从 0 开始。
    ///   - elapsedSinceTypingBegan: 从显示输入指示到模型完成生成的时间。
    ///     仅首条消息扣除此时间。
    ///   - variation: 0...1 的轻微随机量，避免每次都呈现机械固定节奏。
    public func delay(
        for text: String,
        messageIndex: Int,
        elapsedSinceTypingBegan: TimeInterval,
        variation: Double
    ) -> TimeInterval {
        let words = text.split(whereSeparator: \.isWhitespace).count
        let visibleCharacters = text.filter { !$0.isWhitespace }.count
        let punctuationPauses = text.filter { ",;:?!\u{2026}\u{2014}".contains($0) }.count
        let clampedVariation = min(max(variation, 0), 1)
        let jitter = (clampedVariation - 0.5) * 0.6
        let continuationPause = messageIndex > 0 ? 0.25 : 0

        // Product pace: ordinary ten-word bubbles take about 6–8 seconds.
        // Long words can take longer; count words and characters as alternatives,
        // rather than charging twice for the same text.
        let simulatedTyping = 0.65
            + continuationPause
            + max(Double(words) * 0.58, Double(visibleCharacters) * 0.11)
            + Double(punctuationPauses) * 0.1
            + jitter
        let target = min(max(simulatedTyping, minimumDelay), maximumDelay)

        guard messageIndex == 0 else { return target }
        let maximumCredit = max(0, target - minimumFirstMessageDelay)
        let generationCredit = min(max(0, elapsedSinceTypingBegan) * 0.45, maximumCredit)
        return max(minimumFirstMessageDelay, target - generationCredit)
    }
}

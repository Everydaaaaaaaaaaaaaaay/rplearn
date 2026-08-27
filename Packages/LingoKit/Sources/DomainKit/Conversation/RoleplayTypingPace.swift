import Foundation

/// 将已经生成好的角色回复按接近真人打字的节奏逐条送达。
///
/// 首条消息会扣除模型已经用于思考和生成的时间，避免在网络等待后再次制造
/// 一段完整延迟；后续消息则保留短暂的输入时间，让连续气泡不会同时出现。
public struct RoleplayTypingPace: Sendable {
    public static let standard = RoleplayTypingPace()

    public let minimumDelay: TimeInterval
    public let maximumDelay: TimeInterval

    public init(
        minimumDelay: TimeInterval = 0.65,
        maximumDelay: TimeInterval = 4.2
    ) {
        self.minimumDelay = minimumDelay
        self.maximumDelay = maximumDelay
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
        let jitter = (clampedVariation - 0.5) * 0.7
        let continuationPause = messageIndex > 0 ? 0.3 : 0

        let simulatedTyping = 0.5
            + continuationPause
            + Double(words) * 0.16
            + Double(visibleCharacters) * 0.015
            + Double(punctuationPauses) * 0.08
            + jitter
        let target = min(max(simulatedTyping, minimumDelay), maximumDelay)

        guard messageIndex == 0 else { return target }
        return max(0, target - max(0, elapsedSinceTypingBegan))
    }
}

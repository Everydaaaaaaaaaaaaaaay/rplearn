import Foundation
import Observation

/// 剧情播放器（@Observable、无 UI 依赖）。
/// 聊天皮肤与竖屏 AVG 共用：advance()/choose()/skipToNextChoiceOrEnd()。
@MainActor
@Observable
public final class StoryPlayer {
    /// 已展示的台词（聊天皮肤把它渲染成气泡列表；AVG 只取最后一条）。
    public struct Line: Sendable, Equatable, Identifiable {
        public let id: Int
        public let speaker: String
        public let text: String
        public let bg: String?
        public let sprite: String?
    }

    public private(set) var history: [Line] = []
    /// 非 nil 时等待用户选择（advance 无效）。
    public private(set) var currentChoices: [StoryChoiceOption]?
    public private(set) var isFinished = false
    public private(set) var flags: [String: Bool] = [:]
    public var isAuto = false

    /// 奖励回调（经组合根接 EconomyService/ItemStore）。
    public var onReward: (@MainActor (StoryReward) -> Void)?
    /// 完结回调（unlocks 交给上层处理）。
    public var onCompleted: (@MainActor ([String]) -> Void)?
    /// 每步状态回调（断点续播持久化用）。
    public var onStateChange: (@MainActor (_ nodeID: String?, _ flags: [String: Bool]) -> Void)?

    private let script: StoryScript
    private var cursor: String?
    /// bg/sprite 缺省沿用上一节点
    private var lastBG: String?
    private var lastSprite: String?

    public init(script: StoryScript, resumeFrom nodeID: String? = nil, flags: [String: Bool] = [:]) {
        self.script = script
        self.cursor = nodeID ?? script.start
        self.flags = flags
    }

    /// 推进一步：产出下一条台词，或停在选项/结尾。
    public func advance() {
        guard !isFinished, currentChoices == nil else { return }
        step(emitLine: true)
    }

    /// 选择一个选项。
    public func choose(_ index: Int) {
        guard let options = currentChoices, options.indices.contains(index) else { return }
        let option = options[index]
        for (flag, value) in option.setFlags ?? [:] {
            flags[flag] = value
        }
        currentChoices = nil
        cursor = option.next
        notifyState()
    }

    /// 快进：连续推进直到遇到选项或结束。
    public func skipToNextChoiceOrEnd() {
        while !isFinished && currentChoices == nil {
            advance()
        }
    }

    // MARK: - 私有

    /// 处理节点直到产出一条台词（line）或停下（choice/end）。
    private func step(emitLine: Bool) {
        while let nodeID = cursor, let node = script.node(nodeID) {
            switch node.payload {
            case .line(let speaker, let text, let bg, let sprite, let next):
                lastBG = bg ?? lastBG
                lastSprite = sprite ?? lastSprite
                history.append(
                    Line(id: history.count, speaker: speaker, text: text, bg: lastBG, sprite: lastSprite)
                )
                cursor = next
                notifyState()
                return
            case .choice(let options):
                currentChoices = options
                notifyState()
                return
            case .branch(let flag, let ifTrue, let ifFalse):
                cursor = flags[flag] == true ? ifTrue : ifFalse
            case .reward(let reward, let next):
                onReward?(reward)
                cursor = next
            case .end(let unlocks):
                isFinished = true
                cursor = nil
                notifyState()
                onCompleted?(unlocks)
                return
            }
        }
    }

    private func notifyState() {
        onStateChange?(cursor, flags)
    }
}

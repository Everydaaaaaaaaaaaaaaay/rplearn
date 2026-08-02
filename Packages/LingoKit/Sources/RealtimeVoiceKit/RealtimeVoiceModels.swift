import Foundation

/// 实时语音页对外暴露的稳定状态；音频和网络细节不泄漏给 UI。
public enum RealtimeVoicePhase: Sendable, Equatable {
    case idle
    case connecting
    case listening
    case thinking
    case speaking
    case paused
    case failed
}

public enum RealtimeVoiceError: LocalizedError, Sendable, Equatable {
    case microphonePermissionDenied
    case speechRecognitionPermissionDenied
    case speechRecognizerUnavailable
    case audioInputUnavailable
    case audioSessionFailed
    case emptyAIResponse

    public var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            "需要麦克风权限才能开始语音对话。"
        case .speechRecognitionPermissionDenied:
            "需要语音识别权限才能理解你说的话。"
        case .speechRecognizerUnavailable:
            "语音识别暂时不可用，请稍后再试。"
        case .audioInputUnavailable:
            "没有检测到可用的麦克风。"
        case .audioSessionFailed:
            "音频设备启动失败，请重新连接耳机或稍后再试。"
        case .emptyAIResponse:
            "角色这次没有生成可播放的回复。"
        }
    }

    public var requiresSettings: Bool {
        self == .microphonePermissionDenied || self == .speechRecognitionPermissionDenied
    }
}

/// ChatFeature 提供的最小会话接口。实时语音核心只消费文本流，不感知聊天存储和模型供应商。
public struct RealtimeVoiceConversationClient: Sendable {
    public typealias ReplyStream = @MainActor @Sendable (
        _ userText: String
    ) async throws -> AsyncThrowingStream<String, Error>
    public typealias SaveAssistant = @MainActor @Sendable (_ spokenText: String) async -> Void

    public let replyStream: ReplyStream
    public let saveAssistant: SaveAssistant

    public init(
        replyStream: @escaping ReplyStream,
        saveAssistant: @escaping SaveAssistant
    ) {
        self.replyStream = replyStream
        self.saveAssistant = saveAssistant
    }
}

/// 识别服务瞬时失败时的恢复节奏。调用方可按产品场景覆盖，默认仅做三次渐进式重试。
public struct SpeechRecognitionRecoveryPolicy: Sendable, Equatable {
    public var retryDelays: [Duration]

    public init(
        retryDelays: [Duration] = [
            .milliseconds(350),
            .milliseconds(900),
            .milliseconds(1_800),
        ]
    ) {
        self.retryDelays = retryDelays
    }
}

@MainActor
public protocol RealtimeSpeechInput: AnyObject {
    var latestTranscript: String { get }
    var onLevel: (@MainActor @Sendable (Double, TimeInterval) -> Void)? { get set }
    var onTranscript: (@MainActor @Sendable (String) -> Void)? { get set }
    var onFailure: (@MainActor @Sendable (String) -> Void)? { get set }

    func start(localeIdentifier: String, contextualStrings: [String]) async throws
    func restartRecognition()
    func setMuted(_ muted: Bool)
    func stop() async
}

@MainActor
public protocol RealtimeSpeechOutput: AnyObject {
    var heardText: String { get }

    func beginResponse(language: String)
    func enqueue(_ text: String)
    func waitUntilFinished() async
    @discardableResult func stop() -> String
}

public enum VoiceActivityEvent: Sendable, Equatable {
    case speechStarted
    case interruption
    case speechEnded
}

public struct VoiceTurnDetectionPolicy: Sendable, Equatable {
    public var activationLevel: Double
    public var releaseLevel: Double
    public var minimumSpeechDuration: TimeInterval
    public var interruptionDuration: TimeInterval
    public var endOfTurnSilence: TimeInterval

    public init(
        activationLevel: Double = 0.12,
        releaseLevel: Double = 0.07,
        minimumSpeechDuration: TimeInterval = 0.18,
        interruptionDuration: TimeInterval = 0.24,
        endOfTurnSilence: TimeInterval = 0.85
    ) {
        self.activationLevel = activationLevel
        self.releaseLevel = releaseLevel
        self.minimumSpeechDuration = minimumSpeechDuration
        self.interruptionDuration = interruptionDuration
        self.endOfTurnSilence = endOfTurnSilence
    }
}

/// 基于端上音量的轻量轮次检测器。语音识别只负责文字，不参与时序判断。
public struct ClientVoiceTurnDetector: Sendable {
    private let policy: VoiceTurnDetectionPolicy
    private var speechStartedAt: TimeInterval?
    private var silenceStartedAt: TimeInterval?
    private var interruptionSent = false

    public init(policy: VoiceTurnDetectionPolicy = .init()) {
        self.policy = policy
    }

    public mutating func ingest(
        level: Double,
        at timestamp: TimeInterval,
        agentIsBusy: Bool
    ) -> [VoiceActivityEvent] {
        var events: [VoiceActivityEvent] = []

        if level >= policy.activationLevel {
            if speechStartedAt == nil {
                speechStartedAt = timestamp
                events.append(.speechStarted)
            }
            silenceStartedAt = nil

            if agentIsBusy,
               !interruptionSent,
               let speechStartedAt,
               timestamp - speechStartedAt >= policy.interruptionDuration {
                interruptionSent = true
                events.append(.interruption)
            }
            return events
        }

        guard let speechStartedAt else { return events }
        guard level <= policy.releaseLevel else { return events }

        if silenceStartedAt == nil {
            silenceStartedAt = timestamp
        }
        guard let silenceStartedAt,
              timestamp - silenceStartedAt >= policy.endOfTurnSilence else {
            return events
        }

        // 最短发言只计算实际有声区间，不能把等待结束的静音也算进去。
        if silenceStartedAt - speechStartedAt >= policy.minimumSpeechDuration {
            events.append(.speechEnded)
        }
        reset()
        return events
    }

    public mutating func reset() {
        speechStartedAt = nil
        silenceStartedAt = nil
        interruptionSent = false
    }
}

/// 把模型 token 流切成自然、可立即排入 TTS 的短句。
public struct StreamingSpeechSegmenter: Sendable {
    private var buffer = ""
    private let maximumWordsWithoutPunctuation: Int

    public init(maximumWordsWithoutPunctuation: Int = 12) {
        self.maximumWordsWithoutPunctuation = max(4, maximumWordsWithoutPunctuation)
    }

    public mutating func append(_ delta: String) -> [String] {
        buffer += delta
        return drainCompleteSegments()
    }

    public mutating func finish() -> [String] {
        var segments = drainCompleteSegments()
        let remainder = SpokenTextSanitizer.sanitize(buffer)
        buffer = ""
        if !remainder.isEmpty {
            segments.append(remainder)
        }
        return segments
    }

    private mutating func drainCompleteSegments() -> [String] {
        var result: [String] = []
        while let boundary = firstSentenceBoundary() ?? wordLimitBoundary() {
            let candidate = String(buffer[..<boundary])
            buffer.removeSubrange(..<boundary)
            let spoken = SpokenTextSanitizer.sanitize(candidate)
            if !spoken.isEmpty {
                result.append(spoken)
            }
        }
        return result
    }

    private func firstSentenceBoundary() -> String.Index? {
        let punctuation: Set<Character> = [".", "?", "!", ";", "\n", "。", "？", "！", "；"]
        guard let index = buffer.firstIndex(where: { punctuation.contains($0) }) else {
            return nil
        }
        return buffer.index(after: index)
    }

    /// 只在单词后的空白处切分，避免模型 token 恰好落在单词中间时读出残词。
    private func wordLimitBoundary() -> String.Index? {
        var inWord = false
        var completedWords = 0
        var index = buffer.startIndex
        while index < buffer.endIndex {
            let character = buffer[index]
            if character.isWhitespace {
                if inWord {
                    completedWords += 1
                    inWord = false
                    if completedWords >= maximumWordsWithoutPunctuation {
                        return buffer.index(after: index)
                    }
                }
            } else {
                inWord = true
            }
            index = buffer.index(after: index)
        }
        return nil
    }
}

public enum SpokenTextSanitizer {
    public static func sanitize(_ text: String) -> String {
        let scalars = text.unicodeScalars.filter { scalar in
            if scalar.properties.isEmojiPresentation { return false }
            if scalar.value == 0x200D || scalar.value == 0xFE0F || scalar.value == 0x20E3 {
                return false
            }
            return scalar != "*" && scalar != "#" && scalar != "`"
        }
        return String(String.UnicodeScalarView(scalars))
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

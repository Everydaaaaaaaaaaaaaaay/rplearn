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
    var onLevel: (@MainActor @Sendable (Double) -> Void)? { get set }
    var onTranscription: (@MainActor @Sendable (RealtimeTranscription) -> Void)? { get set }
    var onFailure: (@MainActor @Sendable (String) -> Void)? { get set }

    func start(localeIdentifier: String, contextualStrings: [String]) async throws
    func restartRecognition()
    func setMuted(_ muted: Bool)
    func stop() async
}

/// 系统语音识别产生的累计文本。最终结果可立即提交，其余结果由会话层做短防抖。
public struct RealtimeTranscription: Sendable, Equatable {
    public let text: String
    public let isFinal: Bool

    public init(text: String, isFinal: Bool) {
        self.text = text
        self.isFinal = isFinal
    }
}

@MainActor
public protocol RealtimeSpeechOutput: AnyObject {
    var heardText: String { get }

    func beginResponse(language: String)
    func enqueue(_ text: String)
    func waitUntilFinished() async
    @discardableResult func stop() -> String
}

/// 一轮语音在最后一次有效转写后等待多久再提交。其余时序交给系统识别结果，不重复实现 VAD。
public struct VoiceTurnPolicy: Sendable, Equatable {
    public var endOfTurnDelay: Duration

    public init(endOfTurnDelay: Duration = .milliseconds(850)) {
        self.endOfTurnDelay = endOfTurnDelay
    }
}

/// 把模型 token 流切成自然、可立即排入 TTS 的短句。
public struct StreamingSpeechSegmenter: Sendable {
    private var buffer: [Character] = []
    private var scannedCharacterCount = 0
    private var isInsideWord = false
    private var completedWordCount = 0
    private let maximumWordsWithoutPunctuation: Int

    private static let sentencePunctuation: Set<Character> = [
        ".", "?", "!", ";", "\n", "。", "？", "！", "；",
    ]

    public init(maximumWordsWithoutPunctuation: Int = 12) {
        self.maximumWordsWithoutPunctuation = max(4, maximumWordsWithoutPunctuation)
    }

    public mutating func append(_ delta: String) -> [String] {
        let previousCount = buffer.count
        buffer.append(contentsOf: delta)

        var result: [String] = []
        let punctuationIndices = buffer.indices.dropFirst(previousCount).filter {
            Self.sentencePunctuation.contains(buffer[$0])
        }
        if let lastPunctuationIndex = punctuationIndices.last {
            var segmentStart = buffer.startIndex
            for punctuationIndex in punctuationIndices {
                appendSanitized(
                    buffer[segmentStart...punctuationIndex],
                    to: &result
                )
                segmentStart = buffer.index(after: punctuationIndex)
            }
            buffer.removeFirst(buffer.distance(
                from: buffer.startIndex,
                to: buffer.index(after: lastPunctuationIndex)
            ))
            resetWordScan()
        }

        drainWordLimitedSegments(into: &result)
        return result
    }

    public mutating func finish() -> [String] {
        var segments: [String] = []
        let remainder = SpokenTextSanitizer.sanitize(String(buffer))
        buffer.removeAll(keepingCapacity: true)
        resetWordScan()
        if !remainder.isEmpty {
            segments.append(remainder)
        }
        return segments
    }

    /// 只在单词后的空白处切分，避免模型 token 恰好落在单词中间时读出残词。
    private mutating func drainWordLimitedSegments(into result: inout [String]) {
        var segmentStart = buffer.startIndex
        var index = buffer.index(buffer.startIndex, offsetBy: scannedCharacterCount)
        while index < buffer.endIndex {
            let character = buffer[index]
            if character.isWhitespace {
                if isInsideWord {
                    completedWordCount += 1
                    isInsideWord = false
                    if completedWordCount >= maximumWordsWithoutPunctuation {
                        let boundary = buffer.index(after: index)
                        appendSanitized(buffer[segmentStart..<boundary], to: &result)
                        segmentStart = boundary
                        completedWordCount = 0
                    }
                }
            } else {
                isInsideWord = true
            }
            index = buffer.index(after: index)
        }

        if segmentStart > buffer.startIndex {
            buffer.removeFirst(buffer.distance(from: buffer.startIndex, to: segmentStart))
        }
        scannedCharacterCount = buffer.count
    }

    private mutating func resetWordScan() {
        scannedCharacterCount = 0
        isInsideWord = false
        completedWordCount = 0
    }

    private func appendSanitized<S: Sequence>(
        _ characters: S,
        to result: inout [String]
    ) where S.Element == Character {
        let spoken = SpokenTextSanitizer.sanitize(String(characters))
        if !spoken.isEmpty {
            result.append(spoken)
        }
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

import Foundation
import SpeechKit

/// 实时语音页的稳定状态。具体 ASR、LLM 和 TTS 实现不会泄漏给界面层。
public enum RealtimeVoicePhase: Sendable, Equatable {
    case idle
    case connecting
    case listening
    case userSpeaking
    case thinking
    case speaking
    case reconnecting
    case paused
    case failed
}

public enum RealtimeVoiceError: LocalizedError, Sendable, Equatable {
    case microphonePermissionDenied
    case speechRecognitionPermissionDenied
    case speechRecognizerUnavailable
    case audioInputUnavailable
    case audioSessionFailed
    case modelPreparationFailed
    case emptyAIResponse

    public var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            "需要麦克风权限才能开始实时语音。"
        case .speechRecognitionPermissionDenied:
            "需要语音识别权限才能使用 Apple 系统识别。"
        case .speechRecognizerUnavailable:
            "Apple 系统识别当前不可用，请稍后重试或切换到内置识别模型。"
        case .audioInputUnavailable:
            "没有检测到可用的麦克风。"
        case .audioSessionFailed:
            "音频设备启动失败，请重新连接耳机或稍后再试。"
        case .modelPreparationFailed:
            "内置语音模型加载失败，请重新启动应用后再试。"
        case .emptyAIResponse:
            "角色这次没有生成可播放的回复。"
        }
    }

    public var requiresSettings: Bool {
        self == .microphonePermissionDenied || self == .speechRecognitionPermissionDenied
    }
}

/// ChatFeature 注入的最小会话接口。RealtimeVoiceKit 只消费文本流，
/// 不感知 SwiftData、角色领域模型，也不绑定某个云端 LLM 供应商。
public struct RealtimeVoiceConversationClient: Sendable {
    public typealias ReplyStream = @MainActor @Sendable (
        _ userText: String
    ) async throws -> AsyncThrowingStream<String, Error>
    public typealias SaveAssistant = @MainActor @Sendable (
        _ spokenText: String,
        _ interrupted: Bool
    ) async -> Void

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

/// 端侧识别模型的准备状态。模型随 App 安装，仅记录本地 Core ML 加载进度。
public struct RealtimeModelPreparation: Sendable, Equatable {
    public enum Stage: Sendable, Equatable {
        case streamingRecognition
        case transcriptRefinement
        case ready
    }

    public let stage: Stage
    public let progress: Double

    public init(stage: Stage, progress: Double) {
        self.stage = stage
        self.progress = min(max(progress, 0), 1)
    }
}

@MainActor
public protocol RealtimeSpeechInput: AnyObject {
    var onLevel: (@MainActor @Sendable (Double) -> Void)? { get set }
    var onSpeechStarted: (@MainActor @Sendable () -> Void)? { get set }
    var onTranscription: (@MainActor @Sendable (RealtimeTranscription) -> Void)? { get set }
    var onPreparation: (@MainActor @Sendable (RealtimeModelPreparation) -> Void)? { get set }
    var onFailure: (@MainActor @Sendable (String) -> Void)? { get set }

    func start() async throws
    func finishCurrentTurn() async
    func setMuted(_ muted: Bool)
    func stop() async
}

/// 流式识别的累计文本。Parakeet EOU 发布 partial，SenseVoice 发布校正后的 final。
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

    func beginResponse(language: String, voiceHint: SpeechVoiceHint?) async
    func enqueue(_ text: String)
    func waitUntilFinished() async
    @discardableResult func stop() async -> String
}

/// partial 长时间不再变化时的兜底端点。优先采用 Parakeet EOU 的语义端点，
/// 这里只避免极端噪声或模型漏报让一轮对话永远悬挂。
public struct VoiceTurnPolicy: Sendable, Equatable {
    public var fallbackEndOfTurnDelay: Duration

    public init(fallbackEndOfTurnDelay: Duration = .milliseconds(1_150)) {
        self.fallbackEndOfTurnDelay = fallbackEndOfTurnDelay
    }
}

/// 把 LLM token 流切成可以尽快送入 TTS、同时仍保持自然韵律的短句。
public struct StreamingSpeechSegmenter: Sendable {
    private var buffer: [Character] = []
    private var scannedCharacterCount = 0
    private var isInsideWord = false
    private var completedWordCount = 0
    private let maximumWordsWithoutPunctuation: Int

    private static let sentencePunctuation: Set<Character> = [
        ".", "?", "!", ";", ":", "\n", "。", "？", "！", "；", "：",
    ]

    public init(maximumWordsWithoutPunctuation: Int = 7) {
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
                appendSanitized(buffer[segmentStart...punctuationIndex], to: &result)
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
        let remainder = SpokenTextSanitizer.sanitize(String(buffer))
        buffer.removeAll(keepingCapacity: true)
        resetWordScan()
        return remainder.isEmpty ? [] : [remainder]
    }

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
        if !spoken.isEmpty { result.append(spoken) }
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

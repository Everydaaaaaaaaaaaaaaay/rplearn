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

@MainActor
public protocol RealtimeSpeechInput: AnyObject {
    var onLevel: (@MainActor @Sendable (Double) -> Void)? { get set }
    var onSpeechStarted: (@MainActor @Sendable () -> Void)? { get set }
    var onTranscription: (@MainActor @Sendable (RealtimeTranscription) -> Void)? { get set }
    var onFailure: (@MainActor @Sendable (String) -> Void)? { get set }

    func start() async throws
    func finishCurrentTurn() async
    func setMuted(_ muted: Bool)
    func stop() async
}

/// Apple Speech 流式识别的累计文本。
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
    var onPlaybackStarted: (@MainActor @Sendable () -> Void)? { get set }
    var heardText: String { get }

    func beginResponse(language: String, voiceHint: SpeechVoiceHint?) async
    func enqueue(_ text: String)
    func waitUntilFinished() async
    @discardableResult func stop() async -> String
}

/// partial 长时间不再变化时的兜底端点，避免系统识别漏报 final 让一轮对话永远悬挂。
public struct VoiceTurnPolicy: Sendable, Equatable {
    public var fallbackEndOfTurnDelay: Duration

    public init(fallbackEndOfTurnDelay: Duration = .milliseconds(1_150)) {
        self.fallbackEndOfTurnDelay = fallbackEndOfTurnDelay
    }
}

/// 把 LLM token 流切成可以尽快送入 TTS、同时仍保持自然韵律的短句。
public struct StreamingSpeechSegmenter: Sendable {
    private var buffer = ""
    private var hasEmitted = false
    private let maximumWordsWithoutPunctuation: Int
    private static let abbreviations: Set<String> = [
        "mr", "mrs", "ms", "dr", "prof", "st", "vs", "e.g", "i.e", "a.m", "p.m",
    ]

    public init(maximumWordsWithoutPunctuation: Int = 14) {
        self.maximumWordsWithoutPunctuation = max(4, maximumWordsWithoutPunctuation)
    }

    public mutating func append(_ delta: String) -> [String] {
        buffer += delta
        var result: [String] = []
        while let boundary = nextBoundary() {
            let segment = SpokenTextSanitizer.sanitize(String(buffer[..<boundary]))
            buffer.removeSubrange(..<boundary)
            if !segment.isEmpty { result.append(segment); hasEmitted = true }
        }
        return result
    }

    public mutating func finish() -> [String] {
        let remainder = SpokenTextSanitizer.sanitize(buffer)
        buffer = ""
        if !remainder.isEmpty { hasEmitted = true }
        return remainder.isEmpty ? [] : [remainder]
    }

    private func nextBoundary() -> String.Index? {
        var words = 0
        var insideWord = false
        let wordLimit = hasEmitted ? maximumWordsWithoutPunctuation : min(7, maximumWordsWithoutPunctuation)
        for index in buffer.indices {
            let character = buffer[index]
            let after = buffer.index(after: index)
            if "?!;:\n。？！；：".contains(character) { return after }
            if character == ".", after < buffer.endIndex {
                let next = buffer[after]
                let token = buffer[..<index].split(whereSeparator: \.isWhitespace).last.map(String.init) ?? ""
                let isInitial = token.count == 1 && token.first?.isLetter == true
                if (next.isWhitespace || next == "\""),
                   !isInitial, !Self.abbreviations.contains(token.lowercased()) {
                    return after
                }
            }
            if character == ",", words >= 4 { return after }
            if character.isWhitespace {
                if insideWord { words += 1; insideWord = false }
                if words >= wordLimit { return after }
            } else {
                insideWord = true
            }
        }
        // A period at the end of a delta may be a decimal/abbreviation prefix.
        // Wait for the next delta (or finish) instead of speaking "3." then "5".
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

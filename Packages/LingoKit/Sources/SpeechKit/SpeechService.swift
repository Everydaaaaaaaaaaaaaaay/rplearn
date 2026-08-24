import AVFoundation
import CoreKit
import Foundation

public extension Notification.Name {
    /// AVSpeechSynthesizer 实际开始一次语音播放。
    static let speechPlaybackDidBegin = Notification.Name("LingoTripSpeechPlaybackDidBegin")
}

private final class SpeechPlaybackDelegateBox: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    var onCompletion: (@Sendable () -> Void)?

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            NotificationCenter.default.post(name: .speechPlaybackDidBegin, object: nil)
        }
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        onCompletion?()
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        onCompletion?()
    }
}

/// 朗读用途。精确发音练习始终保留给可控的系统语音；角色台词可使用自然度更高的模型。
public enum SpeechPurpose: Sendable, Equatable {
    case general
    case characterDialogue
    case pronunciation
    /// 持续双工模式：TTS 播放时保留麦克风与系统回声消除。
    case realtimeConversation
}

/// 可选角色提示。SpeechKit 不依赖角色领域模型，只接收稳定、最小的选声信息。
public struct SpeechVoiceHint: Sendable, Equatable {
    public let stableID: String
    public let gender: String?
    public let nationality: String?

    public init(stableID: String, gender: String? = nil, nationality: String? = nil) {
        self.stableID = stableID
        self.gender = gender
        self.nationality = nationality
    }
}

/// 一次朗读请求。新增引擎或选声策略时，业务层无需了解具体 TTS 实现。
public struct SpeechRequest: Sendable, Equatable {
    public let text: String
    public let language: String
    public let purpose: SpeechPurpose
    public let voiceHint: SpeechVoiceHint?
    /// nil 表示跟随全局设置；设置页试听可临时指定而不改变用户偏好。
    public let engine: SpeechSynthesisEngine?

    public init(
        text: String,
        language: String = "en-US",
        purpose: SpeechPurpose = .general,
        voiceHint: SpeechVoiceHint? = nil,
        engine: SpeechSynthesisEngine? = nil
    ) {
        self.text = text
        self.language = language
        self.purpose = purpose
        self.voiceHint = voiceHint
        self.engine = engine
    }
}

/// 语音朗读服务。具体引擎、随包模型资源和回退策略都隐藏在协议后。
public protocol SpeechService: Sendable {
    func speak(_ request: SpeechRequest) async
    /// 播放并等待真实结束。实时语音按短分句串行调用，普通朗读无需使用。
    func speakAndWait(_ request: SpeechRequest) async
    func stopSpeaking() async
    /// 用户在系统设置里增删语音后刷新音源缓存（默认空实现）。
    func refreshVoices() async
}

extension SpeechService {
    public func speak(_ text: String) async {
        await speak(SpeechRequest(text: text))
    }

    /// 兼容现有调用点的轻量入口。language 为 BCP-47 口音（en-GB/en-AU/en-US）。
    public func speak(_ text: String, language: String) async {
        await speak(SpeechRequest(text: text, language: language))
    }

    public func refreshVoices() async {}

    public func speakAndWait(_ request: SpeechRequest) async {
        await speak(request)
    }
}

/// Apple 本地 TTS：AVSpeechSynthesizer，按口音选择最高质量 voice。
public actor AppleTTSService: SpeechService {
    private let synthesizer: AVSpeechSynthesizer
    private let delegateBox: SpeechPlaybackDelegateBox
    private let audioSession: AudioSessionCoordinator
    private var voiceCache: [String: AVSpeechSynthesisVoice] = [:]
    private var completionWaiters: [CheckedContinuation<Void, Never>] = []

    public init(audioSession: AudioSessionCoordinator) {
        let synthesizer = AVSpeechSynthesizer()
        let delegateBox = SpeechPlaybackDelegateBox()
        synthesizer.delegate = delegateBox
        self.synthesizer = synthesizer
        self.delegateBox = delegateBox
        self.audioSession = audioSession
        delegateBox.onCompletion = { [weak self] in
            Task { await self?.playbackDidComplete() }
        }
    }

    public func speak(_ request: SpeechRequest) async {
        guard !request.text.isEmpty else { return }
        let mode: AudioSessionCoordinator.Mode = request.purpose == .realtimeConversation
            ? .conversation
            : .playback
        try? await audioSession.activate(mode)
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
            resumeCompletionWaiters()
        }
        let utterance = AVSpeechUtterance(string: request.text)
        utterance.voice = bestVoice(for: request.language)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
        utterance.postUtteranceDelay = 0.1
        synthesizer.speak(utterance)
    }

    public func speakAndWait(_ request: SpeechRequest) async {
        await speak(request)
        guard synthesizer.isSpeaking else { return }
        await withCheckedContinuation { continuation in
            completionWaiters.append(continuation)
        }
    }

    public func stopSpeaking() async {
        synthesizer.stopSpeaking(at: .immediate)
        resumeCompletionWaiters()
    }

    /// 是否已有增强/高级音质（供设置页引导用户到系统设置下载增强语音）。
    public func hasEnhancedVoice(for language: String) -> Bool {
        guard let voice = bestVoice(for: language) else { return false }
        return voice.quality != .default
    }

    private func bestVoice(for language: String) -> AVSpeechSynthesisVoice? {
        if let cached = voiceCache[language] {
            return cached
        }
        let voice = Self.selectBestVoice(from: AVSpeechSynthesisVoice.speechVoices(), language: language)
        if let voice {
            voiceCache[language] = voice
        }
        return voice
    }

    /// 刷新语音缓存：用户在系统设置里下载/删除语音后调用，使新音源立即生效。
    public func refreshVoices() {
        voiceCache.removeAll()
    }

    private func playbackDidComplete() {
        resumeCompletionWaiters()
    }

    private func resumeCompletionWaiters() {
        let waiters = completionWaiters
        completionWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    /// AVSpeechSynthesisVoiceQuality → 数值档：premium 3 > enhanced 2 > default(含其它) 1。
    static func qualityRank(_ quality: AVSpeechSynthesisVoiceQuality) -> Int {
        switch quality {
        case .premium: 3
        case .enhanced: 2
        default: 1
        }
    }

    /// 同一质量档内优先挑选、自然度口碑较好的 Apple 语音（按名字包含匹配）。
    static let preferredVoiceNames: Set<String> = [
        "Ava", "Zoe", "Samantha", "Allison", "Nathan", "Evan", // 美音
        "Serena", "Stephanie", "Kate", "Daniel", "Oliver",     // 英音
        "Karen", "Matilda", "Lee",                             // 澳音
        "Moira", "Rishi", "Tessa",                             // 爱尔兰 / 印度 / 南非
    ]

    /// 自然度优先的英语语音选择：
    /// ① 目标口音本身已装增强/高级音质 → 口音与自然度兼得，用它；
    /// ② 否则在全部英语语音里按「质量 > 口音匹配 > 优先命名」挑最自然的（宁可换口音也不用机械音）；
    /// ③ 都没有 → 回退系统按语言给的默认音。
    /// 效果：用户只要下载任意一款英语增强/高级语音，全 App 立即摆脱机械音。
    public nonisolated static func selectBestVoice(
        from voices: [AVSpeechSynthesisVoice],
        language: String
    ) -> AVSpeechSynthesisVoice? {
        guard let index = rankBestIndex(
            candidates: voices.map { ($0.language, qualityRank($0.quality), $0.name) },
            target: language
        ) else {
            return AVSpeechSynthesisVoice(language: language)
        }
        return voices[index]
    }

    /// 纯排序逻辑（不依赖真实 voice 目录，可单测）。返回最佳候选在数组中的下标。
    static func rankBestIndex(
        candidates: [(language: String, qualityRank: Int, name: String)],
        target: String
    ) -> Int? {
        typealias Candidate = (language: String, qualityRank: Int, name: String)
        let english = candidates.enumerated().filter { $0.element.language.hasPrefix("en") }
        guard !english.isEmpty else { return nil }

        func sameAccent(_ c: Candidate) -> Bool {
            c.language.caseInsensitiveCompare(target) == .orderedSame
        }
        func nameBonus(_ c: Candidate) -> Int {
            preferredVoiceNames.contains { c.name.localizedCaseInsensitiveContains($0) } ? 1 : 0
        }

        // ① 目标口音内已有增强/高级（qualityRank >= 2），口音自然两全。
        let accentNatural = english.filter { sameAccent($0.element) && $0.element.qualityRank >= 2 }
        if let best = accentNatural.max(by: {
            ($0.element.qualityRank, nameBonus($0.element)) < ($1.element.qualityRank, nameBonus($1.element))
        }) {
            return best.offset
        }

        // ② 自然度优先，必要时跨口音：质量 > 口音匹配 > 优先命名。
        return english.max(by: { lhs, rhs in
            (lhs.element.qualityRank, sameAccent(lhs.element) ? 1 : 0, nameBonus(lhs.element))
                < (rhs.element.qualityRank, sameAccent(rhs.element) ? 1 : 0, nameBonus(rhs.element))
        })?.offset
    }

    // MARK: - 语音音质报告（设置页引导下载）

    /// 全部英语语音里能达到的最高自然度（跨口音），驱动「是否建议下载」的总提示。
    public nonisolated static func bestAvailableEnglishQuality() -> VoiceReport.Quality {
        let english = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
        guard let best = english.max(by: { qualityRank($0.quality) < qualityRank($1.quality) }) else {
            return .unavailable
        }
        return VoiceReport.Quality(quality: best.quality)
    }

    /// 逐口音（本口音内）最佳音质，用于设置页分口音展示与下载引导。
    public nonisolated static func voiceReports(
        for languages: [String] = ["en-US", "en-GB", "en-AU"]
    ) -> [VoiceReport] {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        return languages.map { language in
            let best = voices
                .filter { $0.language.caseInsensitiveCompare(language) == .orderedSame }
                .max(by: { qualityRank($0.quality) < qualityRank($1.quality) })
            return VoiceReport(
                language: language,
                accentLabel: AccentMapper.accentLabel(for: language),
                voiceName: best?.name,
                quality: best.map { VoiceReport.Quality(quality: $0.quality) } ?? .unavailable
            )
        }
    }
}

/// 首次播放时的高级语音提示规则，独立为纯逻辑以避免页面生命周期误触发。
public enum VoiceUpgradePromptPolicy {
    public static func shouldPresent(
        isSuppressed: Bool,
        hasPresented: Bool,
        isOnboarding: Bool,
        quality: @autoclosure () -> VoiceReport.Quality
    ) -> Bool {
        !isSuppressed
            && !hasPresented
            && !isOnboarding
            && !quality().isNatural
    }
}

/// 语音音质报告：单个口音当前可用的最佳音源与自然度档位。
public struct VoiceReport: Sendable, Equatable, Identifiable {
    public enum Quality: Int, Sendable, Comparable {
        case unavailable = 0
        case standard = 1
        case enhanced = 2
        case premium = 3

        public init(quality: AVSpeechSynthesisVoiceQuality) {
            switch quality {
            case .premium: self = .premium
            case .enhanced: self = .enhanced
            default: self = .standard
            }
        }

        public static func < (lhs: Quality, rhs: Quality) -> Bool { lhs.rawValue < rhs.rawValue }

        /// 增强/高级才算「自然」，标准音即机械音。
        public var isNatural: Bool { self >= .enhanced }

        public var label: String {
            switch self {
            case .premium: "高级"
            case .enhanced: "增强"
            case .standard: "标准"
            case .unavailable: "未安装"
            }
        }
    }

    public var id: String { language }
    public let language: String
    public let accentLabel: String
    public let voiceName: String?
    public let quality: Quality

    public init(language: String, accentLabel: String, voiceName: String?, quality: Quality) {
        self.language = language
        self.accentLabel = accentLabel
        self.voiceName = voiceName
        self.quality = quality
    }
}

/// 角色国籍 → TTS 口音映射。
public enum AccentMapper {
    public static func language(forNationality nationality: String) -> String {
        switch nationality.lowercased() {
        case "british", "english", "uk": "en-GB"
        case "australian", "australia": "en-AU"
        case "american", "usa", "us": "en-US"
        case "irish": "en-IE"
        case "indian": "en-IN"
        case "south african": "en-ZA"
        default: "en-US"
        }
    }

    /// BCP-47 口音 → 中文短标签（设置页展示用）。
    public static func accentLabel(for language: String) -> String {
        switch language {
        case "en-US": "美式"
        case "en-GB": "英式"
        case "en-AU": "澳式"
        case "en-IN": "印度"
        case "en-IE": "爱尔兰"
        case "en-ZA": "南非"
        default: language
        }
    }
}

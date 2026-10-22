import AVFoundation
import CoreKit
import Foundation

public extension Notification.Name {
    /// Posted only after audio finishes naturally, never when playback is cancelled.
    static let speechPlaybackDidFinish = Notification.Name("LingoTripSpeechPlaybackDidFinish")
    /// Posted when speech audio actually begins playing.
    static let speechPlaybackDidBegin = Notification.Name("LingoTripSpeechPlaybackDidBegin")
}

private final class SpeechPlaybackDelegateBox: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    var onCompletion: (@Sendable (UUID) -> Void)?
    private let lock = NSLock()
    private var playbackIDs: [ObjectIdentifier: (playback: UUID?, completion: UUID)] = [:]

    func register(_ utterance: AVSpeechUtterance, id: UUID?, completion: UUID) {
        lock.withLock { playbackIDs[ObjectIdentifier(utterance)] = (id, completion) }
    }

    func clearPlaybackIDs() { lock.withLock { playbackIDs.removeAll() } }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {
        let id = lock.withLock { playbackIDs[ObjectIdentifier(utterance)]?.playback }
        Task { @MainActor in
            NotificationCenter.default.post(name: .speechPlaybackDidBegin, object: id)
        }
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        if let entry = lock.withLock({ playbackIDs.removeValue(forKey: ObjectIdentifier(utterance)) }) {
            onCompletion?(entry.completion)
            Task { @MainActor in
                NotificationCenter.default.post(name: .speechPlaybackDidFinish, object: entry.playback)
            }
        }
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        if let entry = lock.withLock({ playbackIDs.removeValue(forKey: ObjectIdentifier(utterance)) }) {
            onCompletion?(entry.completion)
        }
    }
}

/// 朗读用途。用于选择音色、播放会话模式与缓存策略，不把具体引擎泄漏给业务层。
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
    /// Optional authored casting; nil keeps the stable automatic voice selection.
    public let supertonicVoice: SupertonicVoice?

    public init(stableID: String, gender: String? = nil, nationality: String? = nil,
                supertonicVoice: SupertonicVoice? = nil) {
        self.stableID = stableID
        self.gender = gender
        self.nationality = nationality
        self.supertonicVoice = supertonicVoice
    }
}

/// Exact bundled voice identifiers for authored character casting.
public typealias SupertonicVoice = CharacterReadingVoice

/// Narrator and user messages share one identity across the app.
public enum StoryVoiceCasting {
    public static let narratorID = "story.narrator"
    public static let narrator = SpeechVoiceHint(stableID: narratorID, gender: "female", nationality: "British", supertonicVoice: .narrator)
    public static func isNarrator(_ speaker: String) -> Bool {
        ["旁白", "出发之后", "narrator", "你", "you", "user"].contains(speaker)
    }
    public static func voice(speaker: String, proposed: SupertonicVoice) -> SupertonicVoice {
        if isNarrator(speaker) { return .narrator }
        switch speaker {
        case "Oliver", "Oliver Bennett": return .m5
        case "Nora", "Isla": return .f5
        case "Ruby", "Ruby Walker": return .f3
        case "Marcus", "Marcus Rivera": return .m3
        default: return proposed
        }
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
    /// Assessment audio must not silently switch engines when synthesis fails.
    public let allowsSystemFallback: Bool
    /// Authored locale-sensitive narration must not trade accent for voice quality.
    public let requiresExactLocale: Bool
    public let delivery: SpeechDelivery?
    /// Correlates actual playback with a realtime phrase; nil for ordinary speech.
    public let playbackID: UUID?

    public init(
        text: String,
        language: String = "en-US",
        purpose: SpeechPurpose = .general,
        voiceHint: SpeechVoiceHint? = nil,
        engine: SpeechSynthesisEngine? = nil,
        allowsSystemFallback: Bool = true,
        requiresExactLocale: Bool = false,
        delivery: SpeechDelivery? = nil,
        playbackID: UUID? = nil
    ) {
        self.text = text
        let resolvedHint = voiceHint ?? (purpose == .general ? StoryVoiceCasting.narrator : nil)
        self.language = resolvedHint?.stableID == StoryVoiceCasting.narratorID && language.hasPrefix("en") && !requiresExactLocale ? "en-GB" : language
        self.purpose = purpose
        self.voiceHint = resolvedHint
        self.engine = engine
        self.allowsSystemFallback = allowsSystemFallback
        self.requiresExactLocale = requiresExactLocale
        self.delivery = delivery
        self.playbackID = playbackID
    }
}

/// Opaque, single-utterance lookahead. PCM stays in SpeechKit and is never persisted.
public struct PreparedSpeech: Sendable {
    let request: SpeechRequest
    let samples: [Float]
}

/// 语音朗读服务。具体引擎、随包模型资源和回退策略都隐藏在协议后。
public protocol SpeechService: Sendable {
    func speak(_ request: SpeechRequest) async
    /// Listening assessments always use live Supertonic; returned PCM is memory-only.
    func synthesizeListening(_ text: String, voice: SupertonicVoice) async throws -> Data
    /// 播放并等待真实结束。实时语音按短分句串行调用，普通朗读无需使用。
    func speakAndWait(_ request: SpeechRequest) async
    /// Prepare at most one upcoming phrase while the current phrase is audibly playing.
    func prepareForPlayback(_ request: SpeechRequest) async -> PreparedSpeech?
    func speakAndWait(_ request: SpeechRequest, prepared: PreparedSpeech?) async
    func stopSpeaking() async
    /// 用户在系统设置里增删语音后刷新音源缓存（默认空实现）。
    func refreshVoices() async
}

extension SpeechService {
    public func synthesizeListening(_ text: String, voice: SupertonicVoice) async throws -> Data {
        throw ListeningSpeechError.unavailable
    }

    public func speak(_ text: String) async {
        await speak(SpeechRequest(text: text))
    }

    /// 兼容现有调用点的轻量入口。language 为 BCP-47 口音（en-GB/en-AU/en-US）。
    public func speak(_ text: String, language: String) async {
        await speak(SpeechRequest(text: text, language: language))
    }

    public func prepareForPlayback(_ request: SpeechRequest) async -> PreparedSpeech? { nil }

    public func speakAndWait(_ request: SpeechRequest, prepared: PreparedSpeech?) async {
        await speakAndWait(request)
    }

    public func refreshVoices() async {}

    public func speakAndWait(_ request: SpeechRequest) async {
        await speak(request)
    }
}

/// 为可重入的 actor 播放流程签发令牌，确保 await 恢复后只有最新请求能继续。
struct SpeechPlaybackRequestGate: Sendable {
    private var generation: UInt64 = 0

    mutating func issue() -> UInt64 {
        generation &+= 1
        return generation
    }

    mutating func invalidate() {
        _ = issue()
    }

    func accepts(_ candidate: UInt64) -> Bool {
        candidate == generation
    }
}

/// Owned by the speech actor. Only the submitted utterance can release its waiter;
/// a queued cancellation callback from a replaced synthesizer is harmless.
struct SpeechUtteranceCompletion {
    private var id: UUID?
    private var waiter: CheckedContinuation<Void, Never>?
    var isPending: Bool { id != nil }

    mutating func begin(_ id: UUID, waiter: CheckedContinuation<Void, Never>? = nil) {
        cancel()
        self.id = id
        self.waiter = waiter
    }

    mutating func finish(_ id: UUID) {
        guard self.id == id else { return }
        cancel()
    }

    mutating func cancel() {
        id = nil
        let pending = waiter
        waiter = nil
        pending?.resume()
    }
}

/// Apple 本地 TTS：AVSpeechSynthesizer，按口音选择最高质量 voice。
public actor AppleTTSService: SpeechService {
    private var synthesizer: AVSpeechSynthesizer
    private let delegateBox: SpeechPlaybackDelegateBox
    private let audioSession: AudioSessionCoordinator
    private var voiceCache: [String: AVSpeechSynthesisVoice] = [:]
    private var completion = SpeechUtteranceCompletion()
    private var requestGate = SpeechPlaybackRequestGate()

    public init(audioSession: AudioSessionCoordinator) {
        let delegateBox = SpeechPlaybackDelegateBox()
        self.delegateBox = delegateBox
        self.synthesizer = Self.makeSynthesizer(delegate: delegateBox)
        self.audioSession = audioSession
        delegateBox.onCompletion = { [weak self] id in
            Task { await self?.playbackDidComplete(id) }
        }
    }

    public func speak(_ request: SpeechRequest) async {
        guard let utterance = await prepareUtterance(request) else { return }
        let id = UUID()
        delegateBox.register(utterance, id: request.playbackID, completion: id)
        completion.begin(id)
        synthesizer.speak(utterance)
    }

    private func prepareUtterance(_ request: SpeechRequest) async -> AVSpeechUtterance? {
        guard !request.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !Task.isCancelled else { return nil }
        let generation = requestGate.issue()
        let mode: AudioSessionCoordinator.Mode = request.purpose == .realtimeConversation
            ? .conversation
            : .playback
        try? await audioSession.activate(mode)
        guard requestGate.accepts(generation), !Task.isCancelled else { return nil }

        // AVSpeechSynthesizer 的 immediate stop 会异步收尾。高速重复点击时如果立刻
        // 复用同一个实例，下一条 utterance 可能在取消过渡态中被静默丢弃。
        if completion.isPending || synthesizer.isSpeaking || synthesizer.isPaused {
            replaceSynthesizer()
        }
        let utterance = AVSpeechUtterance(string: request.text)
        if request.requiresExactLocale {
            guard let voice = Self.exactLocaleVoice(from: AVSpeechSynthesisVoice.speechVoices(),
                                                   language: request.language, gender: request.voiceHint?.gender) else {
                Log.speech.warning("所需口音的系统语音不可用，未改用其他口音")
                return nil
            }
            utterance.voice = voice
        } else {
            utterance.voice = characterVoice(for: request) ?? bestVoice(for: request.language)
        }
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92 * (request.narrativeDelivery?.speedMultiplier ?? 1)
        utterance.preUtteranceDelay = request.narrativeDelivery?.leadingPause ?? 0
        utterance.postUtteranceDelay = 0.1 + (request.narrativeDelivery?.trailingPause ?? 0)
        return utterance
    }

    public func speakAndWait(_ request: SpeechRequest) async {
        guard let utterance = await prepareUtterance(request) else { return }
        await withCheckedContinuation { continuation in
            // Register before submitting: startup and punctuation pauses are not completion.
            let id = UUID()
            delegateBox.register(utterance, id: request.playbackID, completion: id)
            completion.begin(id, waiter: continuation)
            synthesizer.speak(utterance)
        }
    }

    public func stopSpeaking() async {
        requestGate.invalidate()
        replaceSynthesizer()
    }

    private nonisolated static func makeSynthesizer(
        delegate: SpeechPlaybackDelegateBox
    ) -> AVSpeechSynthesizer {
        let synthesizer = AVSpeechSynthesizer()
        synthesizer.delegate = delegate
        return synthesizer
    }

    /// 丢弃处于 stopping/cancelling 状态的实例，让下一次点击始终从干净状态开始。
    private func replaceSynthesizer() {
        let previous = synthesizer
        previous.delegate = nil
        delegateBox.clearPlaybackIDs()
        if previous.isSpeaking || previous.isPaused {
            previous.stopSpeaking(at: .immediate)
        }
        synthesizer = Self.makeSynthesizer(delegate: delegateBox)
        completion.cancel()
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

    private func characterVoice(for request: SpeechRequest) -> AVSpeechSynthesisVoice? {
        guard (request.purpose == .characterDialogue || request.purpose == .realtimeConversation || request.voiceHint?.stableID == StoryVoiceCasting.narratorID), request.language.lowercased().hasPrefix("en"),
              let hint = request.voiceHint, let genderName = hint.gender?.lowercased(),
              ["male", "female"].contains(genderName) else { return nil }
        let key = "\(request.language)-\(hint.stableID)-\(hint.gender ?? "")"
        if let voice = voiceCache[key] { return voice }
        let gender: AVSpeechSynthesisVoiceGender = genderName == "male" ? .male : .female
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let narrator = Self.selectBestVoice(from: voices.filter { $0.language.hasPrefix("en") && $0.gender == .female }, language: "en-GB")
        if hint.stableID == StoryVoiceCasting.narratorID { return narrator }
        let candidates = voices.filter {
            $0.language.hasPrefix("en") && $0.gender == gender && $0.identifier != narrator?.identifier
        }
        let pool = candidates.isEmpty ? voices.filter { $0.language.hasPrefix("en") && $0.identifier != narrator?.identifier } : candidates
        let voice = Self.selectBestVoice(from: pool, language: request.language)
        if let voice { voiceCache[key] = voice }
        return voice
    }

    static func exactLocaleVoice(from voices: [AVSpeechSynthesisVoice], language: String, gender: String?) -> AVSpeechSynthesisVoice? {
        let candidates = voices.filter { $0.language.caseInsensitiveCompare(language) == .orderedSame }
        let preferredGender: AVSpeechSynthesisVoiceGender = gender?.lowercased() == "male" ? .male : .female
        let matchingGender = candidates.filter { $0.gender == preferredGender }
        let pool = matchingGender.isEmpty ? candidates : matchingGender
        if let voice = pool.sorted(by: { qualityRank($0.quality) > qualityRank($1.quality)
            || ($0.quality == $1.quality && $0.identifier < $1.identifier) }).first { return voice }
        guard let voice = AVSpeechSynthesisVoice(language: language),
              voice.language.caseInsensitiveCompare(language) == .orderedSame else { return nil }
        return voice
    }

    /// 刷新语音缓存：用户在系统设置里下载/删除语音后调用，使新音源立即生效。
    public func refreshVoices() {
        voiceCache.removeAll()
    }

    private func playbackDidComplete(_ id: UUID) {
        completion.finish(id)
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

    /// 一次扫描产生设置页所需的完整音质快照。
    public nonisolated static func voiceCatalogSnapshot(
        for languages: [String] = ["en-US", "en-GB", "en-AU"]
    ) -> VoiceCatalogSnapshot {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let english = voices.filter { $0.language.hasPrefix("en") }
        let bestQuality = english
            .max(by: { qualityRank($0.quality) < qualityRank($1.quality) })
            .map { VoiceReport.Quality(quality: $0.quality) }
            ?? .unavailable
        let reports = languages.map { language in
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
        return VoiceCatalogSnapshot(reports: reports, bestQuality: bestQuality)
    }

    /// 全部英语语音里能达到的最高自然度（跨口音），驱动「是否建议下载」的总提示。
    public nonisolated static func bestAvailableEnglishQuality() -> VoiceReport.Quality {
        voiceCatalogSnapshot().bestQuality
    }

    /// 逐口音（本口音内）最佳音质，用于设置页分口音展示与下载引导。
    public nonisolated static func voiceReports(
        for languages: [String] = ["en-US", "en-GB", "en-AU"]
    ) -> [VoiceReport] {
        voiceCatalogSnapshot(for: languages).reports
    }
}

public struct VoiceCatalogSnapshot: Sendable, Equatable {
    public let reports: [VoiceReport]
    public let bestQuality: VoiceReport.Quality

    public init(reports: [VoiceReport], bestQuality: VoiceReport.Quality) {
        self.reports = reports
        self.bestQuality = bestQuality
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
        if CharacterReadingVoice.isBritish(nationality) { return "en-GB" }
        return switch nationality.lowercased() {
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

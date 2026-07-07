import AVFoundation
import CoreKit

/// 语音朗读服务。隐藏在协议后，未来可换云端 TTS（plan.md 决策 2）。
public protocol SpeechService: Sendable {
    /// 朗读一段英文。language 为 BCP-47 口音（en-GB/en-AU/en-US）。
    func speak(_ text: String, language: String) async
    func stopSpeaking() async
}

extension SpeechService {
    public func speak(_ text: String) async {
        await speak(text, language: "en-US")
    }
}

/// Apple 本地 TTS：AVSpeechSynthesizer，按口音选择最高质量 voice。
public actor AppleTTSService: SpeechService {
    private let synthesizer = AVSpeechSynthesizer()
    private let audioSession: AudioSessionCoordinator
    private var voiceCache: [String: AVSpeechSynthesisVoice] = [:]

    public init(audioSession: AudioSessionCoordinator) {
        self.audioSession = audioSession
    }

    public func speak(_ text: String, language: String) async {
        guard !text.isEmpty else { return }
        try? await audioSession.activate(.playback)
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = bestVoice(for: language)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
        utterance.postUtteranceDelay = 0.1
        synthesizer.speak(utterance)
    }

    public func stopSpeaking() async {
        synthesizer.stopSpeaking(at: .immediate)
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

    /// 质量优先级 premium > enhanced > default；同口音优先，找不到退回任意英语。
    static func selectBestVoice(from voices: [AVSpeechSynthesisVoice], language: String) -> AVSpeechSynthesisVoice? {
        func qualityRank(_ voice: AVSpeechSynthesisVoice) -> Int {
            switch voice.quality {
            case .premium: 2
            case .enhanced: 1
            default: 0
            }
        }
        let sameAccent = voices
            .filter { $0.language.caseInsensitiveCompare(language) == .orderedSame }
            .max { qualityRank($0) < qualityRank($1) }
        if let sameAccent {
            return sameAccent
        }
        return voices
            .filter { $0.language.hasPrefix("en") }
            .max { qualityRank($0) < qualityRank($1) }
            ?? AVSpeechSynthesisVoice(language: language)
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
}

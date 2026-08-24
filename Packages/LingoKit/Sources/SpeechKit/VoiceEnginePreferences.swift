import Foundation

/// 可独立切换的语音合成引擎。业务请求默认跟随此设置，也可在试听时临时覆盖。
public enum SpeechSynthesisEngine: String, CaseIterable, Identifiable, Sendable {
    case system
    case pocketTTS

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .system: "Apple 系统语音"
        case .pocketTTS: "Pocket TTS"
        }
    }
}

/// 实时会话使用的语音识别引擎。切换后从下一次实时会话开始生效。
public enum SpeechRecognitionEngine: String, CaseIterable, Identifiable, Sendable {
    case system
    case enhancedOnDevice

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .system: "Apple 系统识别"
        case .enhancedOnDevice: "Parakeet + SenseVoice"
        }
    }
}

/// UserDefaults 键与迁移只在这里维护，具体模型和设置 UI 不互相依赖。
public enum VoiceEnginePreferences {
    public static let synthesisEngineKey = "lingotrip.voice.synthesisEngine"
    public static let recognitionEngineKey = "lingotrip.voice.recognitionEngine"
    private static let legacyPocketEnabledKey = "lingotrip.pocketTTS.enabled"

    public static func synthesisEngine(
        defaults: UserDefaults = .standard
    ) -> SpeechSynthesisEngine {
        if let raw = defaults.string(forKey: synthesisEngineKey),
           let engine = SpeechSynthesisEngine(rawValue: raw) {
            return engine
        }
        if defaults.object(forKey: legacyPocketEnabledKey) != nil {
            return defaults.bool(forKey: legacyPocketEnabledKey) ? .pocketTTS : .system
        }
        return .pocketTTS
    }

    public static func setSynthesisEngine(
        _ engine: SpeechSynthesisEngine,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(engine.rawValue, forKey: synthesisEngineKey)
        defaults.set(engine == .pocketTTS, forKey: legacyPocketEnabledKey)
    }

    public static func recognitionEngine(
        defaults: UserDefaults = .standard
    ) -> SpeechRecognitionEngine {
        guard let raw = defaults.string(forKey: recognitionEngineKey) else {
            return .enhancedOnDevice
        }
        return SpeechRecognitionEngine(rawValue: raw) ?? .enhancedOnDevice
    }

    public static func setRecognitionEngine(
        _ engine: SpeechRecognitionEngine,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(engine.rawValue, forKey: recognitionEngineKey)
    }
}

import Foundation

/// 可独立切换的语音合成引擎。业务请求默认跟随此设置，也可在试听时临时覆盖。
public enum SpeechSynthesisEngine: String, CaseIterable, Identifiable, Sendable {
    case system
    case supertonic3

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .system: "Apple 系统语音"
        case .supertonic3: "Supertonic-3"
        }
    }
}

/// UserDefaults 键与迁移只在这里维护，具体模型和设置 UI 不互相依赖。
public enum VoiceEnginePreferences {
    public static let synthesisEngineKey = "lingotrip.voice.synthesisEngine"
    private static let legacyPocketEnabledKey = "lingotrip.pocketTTS.enabled"

    public static func synthesisEngine(
        defaults: UserDefaults = .standard
    ) -> SpeechSynthesisEngine {
        if let raw = defaults.string(forKey: synthesisEngineKey) {
            // 已安装旧版本的用户无感迁移：Pocket 被 Supertonic-3 完整替代。
            if raw == "pocketTTS" { return .supertonic3 }
            if let engine = SpeechSynthesisEngine(rawValue: raw) { return engine }
        }
        if defaults.object(forKey: legacyPocketEnabledKey) != nil {
            return defaults.bool(forKey: legacyPocketEnabledKey) ? .supertonic3 : .system
        }
        return .supertonic3
    }

    public static func setSynthesisEngine(
        _ engine: SpeechSynthesisEngine,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(engine.rawValue, forKey: synthesisEngineKey)
        defaults.set(engine != .system, forKey: legacyPocketEnabledKey)
    }

}

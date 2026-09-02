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
    private static let supertonicDefaultMigrationKey =
        "lingotrip.voice.supertonicDefaultMigration.v1"

    public static func synthesisEngine(
        defaults: UserDefaults = .standard
    ) -> SpeechSynthesisEngine {
        // 旧安装可能把 Apple 或已移除的 Pocket 选择持久化下来。升级后的首次读取
        // 统一切到随包 Supertonic；之后用户主动选择 Apple 时仍尊重该选择。
        guard defaults.bool(forKey: supertonicDefaultMigrationKey) else {
            setSynthesisEngine(.supertonic3, defaults: defaults)
            return .supertonic3
        }

        if let raw = defaults.string(forKey: synthesisEngineKey) {
            if raw == "pocketTTS" {
                setSynthesisEngine(.supertonic3, defaults: defaults)
                return .supertonic3
            }
            if let engine = SpeechSynthesisEngine(rawValue: raw) { return engine }
        }

        setSynthesisEngine(.supertonic3, defaults: defaults)
        return .supertonic3
    }

    public static func setSynthesisEngine(
        _ engine: SpeechSynthesisEngine,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(engine.rawValue, forKey: synthesisEngineKey)
        defaults.set(true, forKey: supertonicDefaultMigrationKey)
        defaults.removeObject(forKey: legacyPocketEnabledKey)
    }

}

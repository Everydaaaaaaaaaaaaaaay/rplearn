import Foundation

/// 将用户选择与请求级覆盖收敛成具体引擎，Feature 层无需知道资源回退策略。
enum SpeechEngineRouter {
    static func resolve(
        request: SpeechRequest,
        selectedEngine: SpeechSynthesisEngine,
        supertonicIsAvailable: Bool
    ) -> SpeechSynthesisEngine {
        // Bundled Supertonic exposes English (`en`), not a regional accent selector.
        if request.requiresExactLocale { return .system }
        let requestedEngine = request.engine ?? selectedEngine
        guard requestedEngine == .supertonic3 else { return .system }
        return supertonicIsAvailable ? .supertonic3 : .system
    }
}

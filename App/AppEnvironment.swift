import CoreKit
import Foundation
import LLMKit

/// 组合根：持有全部服务实例并向下注入。后续单元逐步填充。
@MainActor
@Observable
final class AppEnvironment {
    let keychain: KeychainStore
    let llmSettings: LLMSettingsStore
    let llmRouter: LLMRouter

    init() {
        let keychain = KeychainStore()
        self.keychain = keychain
        let settings = LLMSettingsStore(keychain: keychain)
        self.llmSettings = settings
        self.llmRouter = LLMRouter {
            try await MainActor.run { try settings.currentConfiguration() }
        }
        Log.app.info("AppEnvironment initialized")
    }
}

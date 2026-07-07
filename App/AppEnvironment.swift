import CoreKit
import DictKit
import Foundation
import LLMKit

/// 组合根：持有全部服务实例并向下注入。后续单元逐步填充。
@MainActor
@Observable
final class AppEnvironment {
    let keychain: KeychainStore
    let llmSettings: LLMSettingsStore
    let llmRouter: LLMRouter
    let dictionary: DictDatabase
    let grammarPoints: GrammarPointStore

    init() {
        let keychain = KeychainStore()
        self.keychain = keychain
        let settings = LLMSettingsStore(keychain: keychain)
        self.llmSettings = settings
        self.llmRouter = LLMRouter {
            try await MainActor.run { try settings.currentConfiguration() }
        }

        // 词典与语法点是随包资源，缺失/损坏属于构建错误，直接崩溃暴露。
        let dictURL = Bundle.main.url(forResource: "ecdict_lite", withExtension: "sqlite")!
        // swiftlint:disable:next force_try
        self.dictionary = try! DictDatabase(databaseURL: dictURL)
        let grammarURL = Bundle.main.url(forResource: "grammar_points", withExtension: "json")!
        // swiftlint:disable:next force_try
        self.grammarPoints = try! GrammarPointStore(url: grammarURL)

        Log.app.info("AppEnvironment initialized")
    }
}

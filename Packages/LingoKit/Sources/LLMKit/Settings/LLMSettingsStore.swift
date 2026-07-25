import CoreKit
import Foundation
import Observation

/// LLM 供应商设置：非敏感配置存 UserDefaults，API Key 存 Keychain（service 按供应商区分）。
@MainActor
@Observable
public final class LLMSettingsStore {
    private enum Keys {
        static let providerKind = "llm.providerKind"
        static let customBaseURL = "llm.customBaseURL"
        static func model(_ kind: LLMProviderKind, _ tier: LLMTier) -> String {
            "llm.model.\(kind.rawValue).\(tier.rawValue)"
        }
        static func apiKey(_ kind: LLMProviderKind) -> String {
            "llm.apiKey.\(kind.rawValue)"
        }
    }

    private let defaults: UserDefaults
    private let keychain: KeychainStore

    public var providerKind: LLMProviderKind {
        didSet { defaults.set(providerKind.rawValue, forKey: Keys.providerKind) }
    }

    public var customBaseURL: String {
        didSet { defaults.set(customBaseURL, forKey: Keys.customBaseURL) }
    }

    /// 内存中的 Key 副本，供 UI 绑定；写入时同步落 Keychain。
    private var apiKeys: [LLMProviderKind: String] = [:]

    public init(defaults: UserDefaults = .standard, keychain: KeychainStore = KeychainStore()) {
        self.defaults = defaults
        self.keychain = keychain
        self.providerKind = defaults.string(forKey: Keys.providerKind)
            .flatMap(LLMProviderKind.init(rawValue:)) ?? .anthropic
        self.customBaseURL = defaults.string(forKey: Keys.customBaseURL) ?? ""
        for kind in LLMProviderKind.allCases {
            apiKeys[kind] = (try? keychain.string(for: Keys.apiKey(kind))) ?? ""
        }
    }

    // MARK: - API Key

    public func apiKey(for kind: LLMProviderKind) -> String {
        apiKeys[kind] ?? ""
    }

    public func setAPIKey(_ key: String, for kind: LLMProviderKind) {
        apiKeys[kind] = key
        do {
            if key.isEmpty {
                try keychain.removeValue(for: Keys.apiKey(kind))
            } else {
                try keychain.setString(key, for: Keys.apiKey(kind))
            }
        } catch {
            Log.llm.error("保存 API Key 到钥匙串失败：\(error)")
        }
    }

    // MARK: - 模型

    public func modelID(for tier: LLMTier, kind: LLMProviderKind? = nil) -> String {
        let kind = kind ?? providerKind
        let stored = defaults.string(forKey: Keys.model(kind, tier)) ?? ""
        return stored.isEmpty ? kind.defaultModelID(for: tier) : stored
    }

    public func setModelID(_ id: String, for tier: LLMTier) {
        defaults.set(id, forKey: Keys.model(providerKind, tier))
    }

    // MARK: - 配置快照

    public func currentConfiguration() throws -> LLMProviderConfig {
        let key = apiKey(for: providerKind)
        // 自定义端点（如本地部署）允许空 Key，云端供应商必须有 Key。
        if key.isEmpty, providerKind != .custom {
            throw LLMError.missingAPIKey
        }
        let baseURLString = providerKind == .custom ? customBaseURL : providerKind.defaultBaseURL
        guard let baseURL = URL(string: baseURLString), baseURL.scheme != nil else {
            throw LLMError.invalidBaseURL(baseURLString)
        }
        var models: [LLMTier: String] = [:]
        for tier in LLMTier.allCases {
            models[tier] = modelID(for: tier)
        }
        return LLMProviderConfig(kind: providerKind, apiKey: key, baseURL: baseURL, models: models)
    }
}

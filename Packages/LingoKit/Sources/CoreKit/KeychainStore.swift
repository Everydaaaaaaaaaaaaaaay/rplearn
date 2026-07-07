import Foundation
import Security

/// 基于系统钥匙串的键值存储，用于保存 API Key 等敏感信息。
/// UserDefaults 只存非敏感配置，敏感值一律走这里。
public struct KeychainStore: Sendable {
    public let service: String

    public init(service: String = "com.lingotrip.app") {
        self.service = service
    }

    public func string(for key: String) throws -> String? {
        guard let data = try data(for: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func setString(_ value: String, for key: String) throws {
        try setData(Data(value.utf8), for: key)
    }

    public func data(for key: String) throws -> Data? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw AppError.keychain(status)
        }
    }

    public func setData(_ data: Data, for key: String) throws {
        let query = baseQuery(for: key)
        let update = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw AppError.keychain(addStatus) }
        default:
            throw AppError.keychain(updateStatus)
        }
    }

    public func removeValue(for key: String) throws {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppError.keychain(status)
        }
    }

    private func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}

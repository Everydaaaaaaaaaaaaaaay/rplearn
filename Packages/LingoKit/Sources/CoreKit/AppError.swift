import Foundation

/// 全 App 统一错误类型。
public enum AppError: Error, Sendable, Equatable {
    case keychain(OSStatus)
    case network(String)
    case llmProvider(String)
    case decoding(String)
    case dictionary(String)
    case storage(String)
    case permissionDenied(String)
}

extension AppError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .keychain(let status): "钥匙串操作失败（错误码 \(status)）"
        case .network(let message): "网络错误：\(message)"
        case .llmProvider(let message): "AI 服务错误：\(message)"
        case .decoding(let message): "数据解析失败：\(message)"
        case .dictionary(let message): "词典错误：\(message)"
        case .storage(let message): "存储错误：\(message)"
        case .permissionDenied(let capability): "缺少权限：\(capability)"
        }
    }
}

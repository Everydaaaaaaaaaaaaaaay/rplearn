import Foundation

/// LLM 调用错误。Router 依据 http 状态码判定是否重试（429/5xx）。
public enum LLMError: Error, Sendable, Equatable {
    case accessRestricted(String)
    case missingAPIKey
    case invalidBaseURL(String)
    case http(status: Int, message: String)
    case emptyResponse
    case invalidResponse(String)
    case refused(String)

    public var isRetryable: Bool {
        switch self {
        case .http(let status, _):
            status == 429 || status >= 500
        default:
            false
        }
    }
}

extension LLMError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .accessRestricted(let message): message
        case .missingAPIKey: "尚未配置 API Key，请前往设置页填写"
        case .invalidBaseURL(let url): "无效的服务地址：\(url)"
        case .http(let status, let message): "服务返回错误（\(status)）：\(message)"
        case .emptyResponse: "模型返回了空内容"
        case .invalidResponse(let detail): "无法解析模型响应：\(detail)"
        case .refused(let detail): "模型拒绝了此请求：\(detail)"
        }
    }
}

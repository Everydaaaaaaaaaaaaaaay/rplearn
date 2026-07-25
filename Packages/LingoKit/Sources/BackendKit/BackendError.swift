import Foundation

public enum BackendClientError: Error, Sendable, Equatable {
    case api(code: String, message: String, requestID: String?, status: Int)
    case invalidResponse
    case signedOut
    case transport(String)

    public var code: String? {
        if case .api(let code, _, _, _) = self { return code }
        return nil
    }
}

extension BackendClientError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .api(let code, let message, _, _):
            switch code {
            case "EMAIL_NOT_VERIFIED": "请先完成邮箱验证。"
            case "INVALID_CREDENTIALS": "邮箱或密码不正确。"
            case "ACCOUNT_UNAVAILABLE": "这个账号目前不可用。"
            case "REFRESH_TOKEN_REUSE_DETECTED": "会话存在安全风险，请重新登录。"
            default: message
            }
        case .invalidResponse:
            "服务器返回了无法识别的响应。"
        case .signedOut:
            "登录已失效，请重新登录。"
        case .transport:
            "无法连接服务器，请检查网络后重试。"
        }
    }
}

struct BackendErrorEnvelope: Decodable, Sendable {
    let code: String
    let message: String
    let requestId: String?
}

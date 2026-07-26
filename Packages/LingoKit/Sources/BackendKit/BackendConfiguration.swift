import Foundation

public struct BackendConfiguration: Sendable, Equatable {
    public let baseURL: URL
    public let requestTimeout: TimeInterval

    public init(baseURL: URL, requestTimeout: TimeInterval = 30) {
        self.baseURL = baseURL
        self.requestTimeout = requestTimeout
    }

    public static var live: BackendConfiguration {
        if let override = ProcessInfo.processInfo.environment["LINGOTRIP_BACKEND_URL"],
           let url = URL(string: override)
        {
            return BackendConfiguration(baseURL: url)
        }
        #if DEBUG
        return BackendConfiguration(baseURL: URL(string: "http://127.0.0.1:8080")!)
        #else
        return BackendConfiguration(baseURL: URL(string: "https://rplearn.haruyuki.cn")!)
        #endif
    }
}

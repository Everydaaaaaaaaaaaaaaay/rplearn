import Foundation

public struct BackendTransportResponse: Sendable {
    public let data: Data
    public let headers: [String: String]
    public let statusCode: Int

    public init(data: Data, headers: [String: String], statusCode: Int) {
        self.data = data
        self.headers = headers
        self.statusCode = statusCode
    }
}

public protocol BackendTransport: Sendable {
    func data(for request: URLRequest) async throws -> BackendTransportResponse
}

public struct URLSessionBackendTransport: BackendTransport {
    private let session: URLSession

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.waitsForConnectivity = true
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: configuration)
        }
    }

    public func data(for request: URLRequest) async throws -> BackendTransportResponse {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BackendClientError.invalidResponse
        }
        let headers = http.allHeaderFields.reduce(into: [String: String]()) { result, entry in
            guard let key = entry.key as? String, let value = entry.value as? String else { return }
            result[key.lowercased()] = value
        }
        return BackendTransportResponse(
            data: data,
            headers: headers,
            statusCode: http.statusCode
        )
    }
}

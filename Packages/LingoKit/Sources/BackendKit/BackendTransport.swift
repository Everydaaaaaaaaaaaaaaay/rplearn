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

public struct BackendLineStreamResponse: Sendable {
    public let headers: [String: String]
    public let lines: AsyncThrowingStream<String, Error>
    public let statusCode: Int

    public init(
        headers: [String: String],
        lines: AsyncThrowingStream<String, Error>,
        statusCode: Int
    ) {
        self.headers = headers
        self.lines = lines
        self.statusCode = statusCode
    }
}

public protocol BackendTransport: Sendable {
    func data(for request: URLRequest) async throws -> BackendTransportResponse
    func lines(for request: URLRequest) async throws -> BackendLineStreamResponse
}

extension BackendTransport {
    public func lines(for request: URLRequest) async throws -> BackendLineStreamResponse {
        let response = try await data(for: request)
        let body = String(decoding: response.data, as: UTF8.self)
        return BackendLineStreamResponse(
            headers: response.headers,
            lines: AsyncThrowingStream { continuation in
                for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
                    continuation.yield(String(line))
                }
                continuation.finish()
            },
            statusCode: response.statusCode
        )
    }
}

public struct URLSessionBackendTransport: BackendTransport {
    private let session: URLSession

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            self.session = URLSession(configuration: Self.defaultSessionConfiguration())
        }
    }

    static func defaultSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        return configuration
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

    public func lines(for request: URLRequest) async throws -> BackendLineStreamResponse {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BackendClientError.invalidResponse
        }
        let headers = Self.headers(from: http)
        let lines = AsyncThrowingStream<String, Error> { continuation in
            let task = Task {
                do {
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        continuation.yield(line)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return BackendLineStreamResponse(
            headers: headers,
            lines: lines,
            statusCode: http.statusCode
        )
    }

    private static func headers(from response: HTTPURLResponse) -> [String: String] {
        response.allHeaderFields.reduce(into: [String: String]()) { result, entry in
            guard let key = entry.key as? String else { return }
            result[key.lowercased()] = String(describing: entry.value)
        }
    }
}

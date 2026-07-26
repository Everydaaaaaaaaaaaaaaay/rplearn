import Foundation

public protocol VoiceMediaBinaryTransport: Sendable {
    func download(from url: URL) async throws -> Data
    func upload(
        _ data: Data,
        to url: URL,
        method: String,
        headers: [String: String]
    ) async throws
}

public struct URLSessionVoiceMediaTransport: VoiceMediaBinaryTransport {
    private let session: URLSession

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.timeoutIntervalForRequest = 120
            configuration.waitsForConnectivity = true
            self.session = URLSession(configuration: configuration)
        }
    }

    public func download(from url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 120)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        try Self.requireSuccess(response)
        return data
    }

    public func upload(
        _ data: Data,
        to url: URL,
        method: String,
        headers: [String: String]
    ) async throws {
        var request = URLRequest(url: url, timeoutInterval: 120)
        request.httpMethod = method
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        let (_, response) = try await session.upload(for: request, from: data)
        try Self.requireSuccess(response)
    }

    private static func requireSuccess(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw VoiceMediaTransportError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw VoiceMediaTransportError.httpStatus(http.statusCode)
        }
    }
}

public enum VoiceMediaTransportError: Error, Sendable, Equatable {
    case httpStatus(Int)
    case invalidResponse
}

import CoreKit
import Foundation

public actor BackendClient {
    private struct RegisterBody: Encodable, Sendable {
        let email: String
        let password: String
    }

    private struct LoginBody: Encodable, Sendable {
        let device: BackendDevice
        let email: String
        let password: String
    }

    private struct RefreshBody: Encodable, Sendable {
        let refreshToken: String
    }

    private struct AppleLoginBody: Encodable, Sendable {
        let authorizationCode: String
        let challengeId: UUID
        let device: BackendDevice
        let identityToken: String
    }

    private struct LogoutBody: Encodable, Sendable {
        let allDevices: Bool
    }

    private struct EmptyBody: Encodable, Sendable {}

    private let configuration: BackendConfiguration
    private let credentialStore: any AuthCredentialStore
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let transport: any BackendTransport
    private var accessToken: String?
    private var accessTokenExpiresAt: Date?
    private var refreshTask: Task<AuthTokenResponse, Error>?

    public init(
        configuration: BackendConfiguration,
        credentialStore: any AuthCredentialStore,
        transport: any BackendTransport = URLSessionBackendTransport()
    ) {
        self.configuration = configuration
        self.credentialStore = credentialStore
        self.transport = transport
    }

    public func cachedIdentity() throws -> AuthIdentity? {
        guard let stored = try credentialStore.load() else { return nil }
        return AuthIdentity(sessionID: stored.sessionID, userID: stored.userID)
    }

    public func restoreSession() async throws -> AuthIdentity? {
        guard let stored = try credentialStore.load() else { return nil }
        guard stored.refreshTokenExpiresAt > .now else {
            try clearSession()
            return nil
        }
        let token = try await refresh(using: stored)
        return AuthIdentity(sessionID: token.sessionId, userID: token.userId)
    }

    public func register(email: String, password: String) async throws {
        let _: AcceptedResponse = try await send(
            path: "/v1/auth/register",
            method: "POST",
            body: RegisterBody(email: email, password: password),
            authenticated: false
        )
    }

    public func resendVerification(email: String) async throws {
        let _: AcceptedResponse = try await send(
            path: "/v1/auth/email/resend",
            method: "POST",
            body: ["email": email],
            authenticated: false
        )
    }

    public func login(
        email: String,
        password: String,
        device: BackendDevice
    ) async throws -> AuthIdentity {
        let token: AuthTokenResponse = try await send(
            path: "/v1/auth/login",
            method: "POST",
            body: LoginBody(device: device, email: email, password: password),
            authenticated: false
        )
        try apply(token)
        return AuthIdentity(sessionID: token.sessionId, userID: token.userId)
    }

    public func appleChallenge() async throws -> AppleAuthChallenge {
        try await send(
            path: "/v1/auth/apple/challenge",
            method: "POST",
            body: EmptyBody(),
            authenticated: false
        )
    }

    public func loginWithApple(
        authorizationCode: String,
        challengeID: UUID,
        identityToken: String,
        device: BackendDevice
    ) async throws -> AuthIdentity {
        let token: AuthTokenResponse = try await send(
            path: "/v1/auth/apple/login",
            method: "POST",
            body: AppleLoginBody(
                authorizationCode: authorizationCode,
                challengeId: challengeID,
                device: device,
                identityToken: identityToken
            ),
            authenticated: false
        )
        try apply(token)
        return AuthIdentity(sessionID: token.sessionId, userID: token.userId)
    }

    public func logout(allDevices: Bool = false) async {
        do {
            try await sendWithoutResponse(
                path: "/v1/auth/logout",
                method: "POST",
                body: LogoutBody(allDevices: allDevices),
                authenticated: true
            )
        } catch {
            // Local credential removal is authoritative for this device even if offline.
        }
        try? clearSession()
    }

    public func get<Response: Decodable & Sendable>(
        _ path: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        try await request(
            path: path,
            method: "GET",
            body: nil,
            queryItems: queryItems,
            authenticated: true,
            retryAfterUnauthorized: true
        )
    }

    public func send<Request: Encodable & Sendable, Response: Decodable & Sendable>(
        path: String,
        method: String,
        body: Request,
        authenticated: Bool = true,
        idempotencyKey: UUID? = nil
    ) async throws -> Response {
        try await request(
            path: path,
            method: method,
            body: try encoder.encode(body),
            queryItems: [],
            authenticated: authenticated,
            idempotencyKey: idempotencyKey,
            retryAfterUnauthorized: authenticated
        )
    }

    /// Uses the registered account when one is available and otherwise sends a
    /// device-scoped guest request. Guest identity is intentionally limited to
    /// endpoints that explicitly opt into this header on the server.
    public func sendWithGuestAccess<
        Request: Encodable & Sendable,
        Response: Decodable & Sendable
    >(
        path: String,
        method: String,
        body: Request,
        guestID: String
    ) async throws -> Response {
        if try hasUsableStoredSessionForGuestAccess() {
            do {
                return try await send(path: path, method: method, body: body)
            } catch {
                guard Self.isAuthenticationFailure(error) else { throw error }
            }
        }
        return try await request(
            path: path,
            method: method,
            body: try encoder.encode(body),
            queryItems: [],
            authenticated: false,
            additionalHeaders: ["x-lingotrip-guest-id": guestID],
            retryAfterUnauthorized: false
        )
    }

    public func sendWithoutResponse<Request: Encodable & Sendable>(
        path: String,
        method: String,
        body: Request,
        authenticated: Bool = true,
        idempotencyKey: UUID? = nil
    ) async throws {
        let _: Data = try await perform(
            path: path,
            method: method,
            body: try encoder.encode(body),
            queryItems: [],
            authenticated: authenticated,
            idempotencyKey: idempotencyKey,
            retryAfterUnauthorized: authenticated
        )
    }

    public func eventStream<Request: Encodable & Sendable>(
        path: String,
        body: Request
    ) async throws -> AsyncThrowingStream<BackendServerSentEvent, Error> {
        try await openEventStream(
            path: path,
            body: try encoder.encode(body),
            authenticated: true,
            additionalHeaders: [:],
            retryAfterUnauthorized: true
        )
    }

    public func eventStreamWithGuestAccess<Request: Encodable & Sendable>(
        path: String,
        body: Request,
        guestID: String
    ) async throws -> AsyncThrowingStream<BackendServerSentEvent, Error> {
        let encodedBody = try encoder.encode(body)
        if try hasUsableStoredSessionForGuestAccess() {
            do {
                return try await openEventStream(
                    path: path,
                    body: encodedBody,
                    authenticated: true,
                    additionalHeaders: [:],
                    retryAfterUnauthorized: true
                )
            } catch {
                guard Self.isAuthenticationFailure(error) else { throw error }
            }
        }
        return try await openEventStream(
            path: path,
            body: encodedBody,
            authenticated: false,
            additionalHeaders: ["x-lingotrip-guest-id": guestID],
            retryAfterUnauthorized: false
        )
    }

    private func request<Response: Decodable & Sendable>(
        path: String,
        method: String,
        body: Data?,
        queryItems: [URLQueryItem],
        authenticated: Bool,
        idempotencyKey: UUID? = nil,
        additionalHeaders: [String: String] = [:],
        retryAfterUnauthorized: Bool
    ) async throws -> Response {
        let data = try await perform(
            path: path,
            method: method,
            body: body,
            queryItems: queryItems,
            authenticated: authenticated,
            idempotencyKey: idempotencyKey,
            additionalHeaders: additionalHeaders,
            retryAfterUnauthorized: retryAfterUnauthorized
        )
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw BackendClientError.invalidResponse
        }
    }

    private func perform(
        path: String,
        method: String,
        body: Data?,
        queryItems: [URLQueryItem],
        authenticated: Bool,
        idempotencyKey: UUID?,
        additionalHeaders: [String: String] = [:],
        retryAfterUnauthorized: Bool
    ) async throws -> Data {
        guard path.hasPrefix("/v1/") else {
            throw BackendClientError.invalidResponse
        }
        let request = try await makeRequest(
            path: path,
            method: method,
            body: body,
            queryItems: queryItems,
            authenticated: authenticated,
            idempotencyKey: idempotencyKey,
            additionalHeaders: additionalHeaders
        )

        let response: BackendTransportResponse
        do {
            response = try await transport.data(for: request)
        } catch let error as BackendClientError {
            throw error
        } catch {
            throw BackendClientError.transport(String(describing: type(of: error)))
        }

        if response.statusCode == 401, authenticated, retryAfterUnauthorized {
            accessToken = nil
            accessTokenExpiresAt = nil
            _ = try await refreshSession()
            return try await perform(
                path: path,
                method: method,
                body: body,
                queryItems: queryItems,
                authenticated: true,
                idempotencyKey: idempotencyKey,
                additionalHeaders: additionalHeaders,
                retryAfterUnauthorized: false
            )
        }
        guard (200..<300).contains(response.statusCode) else {
            throw apiError(
                data: response.data,
                headers: response.headers,
                statusCode: response.statusCode
            )
        }
        return response.data
    }

    private func makeRequest(
        path: String,
        method: String,
        body: Data?,
        queryItems: [URLQueryItem],
        authenticated: Bool,
        idempotencyKey: UUID?,
        additionalHeaders: [String: String] = [:]
    ) async throws -> URLRequest {
        let endpoint = configuration.baseURL.appendingPathComponent(String(path.dropFirst()))
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw BackendClientError.invalidResponse
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw BackendClientError.invalidResponse
        }
        var request = URLRequest(
            url: url,
            timeoutInterval: configuration.requestTimeout
        )
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(UUID().uuidString.lowercased(), forHTTPHeaderField: "x-request-id")
        if let idempotencyKey {
            request.setValue(idempotencyKey.uuidString.lowercased(), forHTTPHeaderField: "idempotency-key")
        }
        for (field, value) in additionalHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }
        if authenticated {
            request.setValue("Bearer \(try await validAccessToken())", forHTTPHeaderField: "authorization")
        }
        return request
    }

    private func openEventStream(
        path: String,
        body: Data,
        authenticated: Bool,
        additionalHeaders: [String: String],
        retryAfterUnauthorized: Bool
    ) async throws -> AsyncThrowingStream<BackendServerSentEvent, Error> {
        guard path.hasPrefix("/v1/") else {
            throw BackendClientError.invalidResponse
        }
        let request = try await makeRequest(
            path: path,
            method: "POST",
            body: body,
            queryItems: [],
            authenticated: authenticated,
            idempotencyKey: nil,
            additionalHeaders: additionalHeaders
        )
        let response: BackendLineStreamResponse
        do {
            response = try await transport.lines(for: request)
        } catch let error as BackendClientError {
            throw error
        } catch {
            throw BackendClientError.transport(String(describing: type(of: error)))
        }
        if response.statusCode == 401, authenticated, retryAfterUnauthorized {
            accessToken = nil
            accessTokenExpiresAt = nil
            _ = try await refreshSession()
            return try await openEventStream(
                path: path,
                body: body,
                authenticated: true,
                additionalHeaders: additionalHeaders,
                retryAfterUnauthorized: false
            )
        }
        guard (200..<300).contains(response.statusCode) else {
            var bodyText = ""
            for try await line in response.lines {
                bodyText += line
                if bodyText.utf8.count >= 8_192 { break }
            }
            throw apiError(
                data: Data(bodyText.utf8),
                headers: response.headers,
                statusCode: response.statusCode
            )
        }
        return Self.parseEventStream(response.lines)
    }

    private func hasStoredSession() throws -> Bool {
        if let accessToken,
           let accessTokenExpiresAt,
           !accessToken.isEmpty,
           accessTokenExpiresAt.timeIntervalSinceNow > 30
        {
            return true
        }
        guard let stored = try credentialStore.load() else { return false }
        guard stored.refreshTokenExpiresAt > .now else {
            try clearSession()
            return false
        }
        return true
    }

    /// 访客可用端点不应因调试/测试安装缺少钥匙串 entitlement 而完全失效。
    /// 这里只降级钥匙串访问错误；凭据解码等其他异常仍向上传递，避免掩盖数据损坏。
    private func hasUsableStoredSessionForGuestAccess() throws -> Bool {
        do {
            return try hasStoredSession()
        } catch let appError as AppError {
            guard case .keychain = appError else { throw appError }
            return false
        }
    }

    private static func isAuthenticationFailure(_ error: Error) -> Bool {
        guard let backendError = error as? BackendClientError else { return false }
        switch backendError {
        case .signedOut:
            return true
        case .api(_, _, _, let status):
            return status == 401
        case .invalidResponse, .transport:
            return false
        }
    }

    private func apiError(
        data: Data,
        headers: [String: String],
        statusCode: Int
    ) -> BackendClientError {
        let envelope = try? decoder.decode(BackendErrorEnvelope.self, from: data)
        return BackendClientError.api(
            code: envelope?.code ?? "HTTP_\(statusCode)",
            message: envelope?.message ?? "Request failed.",
            requestID: envelope?.requestId ?? headers["x-request-id"],
            status: statusCode
        )
    }

    private static func parseEventStream(
        _ lines: AsyncThrowingStream<String, Error>
    ) -> AsyncThrowingStream<BackendServerSentEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var eventName: String?
                do {
                    for try await line in lines {
                        try Task.checkCancellation()
                        if line.hasPrefix("event:") {
                            eventName = fieldValue(line)
                        } else if line.hasPrefix("data:") {
                            continuation.yield(
                                BackendServerSentEvent(
                                    name: eventName,
                                    data: fieldValue(line)
                                )
                            )
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func fieldValue(_ line: String) -> String {
        guard let separator = line.firstIndex(of: ":") else { return "" }
        let raw = line[line.index(after: separator)...]
        return raw.first == " " ? String(raw.dropFirst()) : String(raw)
    }

    private func validAccessToken() async throws -> String {
        if let accessToken,
           let accessTokenExpiresAt,
           accessTokenExpiresAt.timeIntervalSinceNow > 30
        {
            return accessToken
        }
        return try await refreshSession().accessToken
    }

    private func refreshSession() async throws -> AuthTokenResponse {
        if let refreshTask {
            return try await refreshTask.value
        }
        guard let stored = try credentialStore.load(),
              stored.refreshTokenExpiresAt > .now
        else {
            try clearSession()
            throw BackendClientError.signedOut
        }
        return try await refresh(using: stored)
    }

    private func refresh(using stored: StoredAuthCredential) async throws -> AuthTokenResponse {
        if let refreshTask {
            return try await refreshTask.value
        }
        let task = Task {
            let response: AuthTokenResponse = try await self.send(
                path: "/v1/auth/refresh",
                method: "POST",
                body: RefreshBody(refreshToken: stored.refreshToken),
                authenticated: false
            )
            return response
        }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let token = try await task.value
            try apply(token)
            return token
        } catch let error as BackendClientError {
            if case .api(_, _, _, let status) = error, status == 401 {
                try? clearSession()
            }
            throw error
        }
    }

    private func apply(_ token: AuthTokenResponse) throws {
        guard token.tokenType.caseInsensitiveCompare("Bearer") == .orderedSame,
              let refreshExpiry = parseISO8601(token.refreshTokenExpiresAt)
        else {
            throw BackendClientError.invalidResponse
        }
        try credentialStore.save(
            StoredAuthCredential(
                refreshToken: token.refreshToken,
                refreshTokenExpiresAt: refreshExpiry,
                sessionID: token.sessionId,
                userID: token.userId
            )
        )
        accessToken = token.accessToken
        accessTokenExpiresAt = Date.now.addingTimeInterval(
            TimeInterval(token.accessTokenExpiresIn)
        )
    }

    private func parseISO8601(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }
        return ISO8601DateFormatter().date(from: value)
    }

    private func clearSession() throws {
        accessToken = nil
        accessTokenExpiresAt = nil
        try credentialStore.remove()
    }
}

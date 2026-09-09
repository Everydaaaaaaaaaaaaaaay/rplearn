import AuthenticationServices
import Foundation
import Observation

public enum AuthPhase: Sendable, Equatable {
    case loading
    case signedIn(AuthIdentity)
    case signedOut
}

@MainActor
@Observable
public final class AuthSession {
    public private(set) var phase: AuthPhase = .loading
    public private(set) var lastError: String?

    private let client: BackendClient
    private let device: BackendDevice

    public init(client: BackendClient, device: BackendDevice) {
        self.client = client
        self.device = device
    }

    public func bootstrap() async {
        #if DEBUG
        if ProcessInfo.processInfo.environment["UI_TEST_FORCE_SIGNED_OUT"] == "1" {
            await client.logout()
            phase = .signedOut
            lastError = nil
            return
        }
        #endif
        do {
            if let appleUserID = try await client.storedAppleUserID() {
                let state = try? await ASAuthorizationAppleIDProvider()
                    .credentialState(forUserID: appleUserID)
                if state == .revoked || state == .notFound || state == .transferred {
                    await client.logout()
                }
            }
            phase = try await client.restoreSession().map(AuthPhase.signedIn) ?? .signedOut
        } catch let error as BackendClientError {
            if case .transport = error, let cached = try? await client.cachedIdentity() {
                phase = .signedIn(cached)
                lastError = error.localizedDescription
            } else {
                phase = .signedOut
                lastError = error.localizedDescription
            }
        } catch {
            phase = .signedOut
            lastError = error.localizedDescription
        }
    }

    public func register(email: String, password: String) async throws {
        try await client.register(email: email, password: password)
    }

    public func resendVerification(email: String) async throws {
        try await client.resendVerification(email: email)
    }

    public func login(email: String, password: String) async throws {
        let identity = try await client.login(
            email: email,
            password: password,
            device: device
        )
        phase = .signedIn(identity)
        lastError = nil
    }

    public func prepareAppleChallenge() async throws -> AppleAuthChallenge {
        try await client.appleChallenge()
    }

    public func loginWithApple(
        authorizationCode: String,
        challengeID: UUID,
        identityToken: String,
        appleUserID: String,
        displayName: String?
    ) async throws {
        let identity = try await client.loginWithApple(
            authorizationCode: authorizationCode,
            challengeID: challengeID,
            identityToken: identityToken,
            appleUserID: appleUserID,
            displayName: displayName,
            device: device
        )
        phase = .signedIn(identity)
        lastError = nil
    }

    public func linkWithApple(
        authorizationCode: String,
        challengeID: UUID,
        identityToken: String,
        appleUserID: String,
        displayName: String?
    ) async throws {
        try await client.linkWithApple(
            authorizationCode: authorizationCode,
            challengeID: challengeID,
            identityToken: identityToken,
            appleUserID: appleUserID,
            displayName: displayName
        )
    }

    public func accountIdentities() async throws -> [AccountIdentity] {
        try await client.accountIdentities()
    }

    public func accountDeviceSessions() async throws -> [AccountDeviceSession] {
        try await client.accountDeviceSessions()
    }

    public func revokeDeviceSession(_ deviceSession: AccountDeviceSession) async throws {
        try await client.revokeDeviceSession(deviceSession.id)
    }

    public func unlinkIdentity(_ identity: AccountIdentity) async throws {
        try await client.unlinkIdentity(identity.id)
        if identity.provider == "apple" {
            try await client.clearStoredAppleUserID()
        }
    }

    @discardableResult
    public func deleteAccount(
        immediately: Bool = true
    ) async throws -> AccountDeletionReceipt {
        let receipt = try await client.deleteAccount(immediately: immediately)
        phase = .signedOut
        lastError = nil
        return receipt
    }

    public func logout(allDevices: Bool = false) async {
        await client.logout(allDevices: allDevices)
        phase = .signedOut
        lastError = nil
    }

    /// 将后端明确拒绝的会话反映到根导航；普通网络错误不退出登录。
    @discardableResult
    public func handleAuthenticationFailure(_ error: Error) -> Bool {
        guard let backendError = error as? BackendClientError else { return false }
        let isAuthenticationFailure: Bool
        switch backendError {
        case .signedOut:
            isAuthenticationFailure = true
        case .api(_, _, _, let status):
            isAuthenticationFailure = status == 401
        case .invalidResponse, .transport:
            isAuthenticationFailure = false
        }
        guard isAuthenticationFailure else { return false }
        phase = .signedOut
        lastError = backendError.localizedDescription
        return true
    }
}

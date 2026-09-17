import Foundation
import Testing
@testable import BackendKit

@Suite("Apple login preparation recovery") @MainActor
struct AppleSignInPreparationTests {
    private func challenge() -> AppleAuthChallenge {
        AppleAuthChallenge(challengeId: UUID(), expiresIn: 300, nonce: "test-nonce")
    }
    private func settle(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(condition())
    }
    private static func sleep(_ seconds: TimeInterval) async throws {
        if seconds > 3 { try await Task.sleep(for: .seconds(3600)) }
        else { await Task.yield(); try Task.checkCancellation() }
    }

    @Test("首次暂时断网会自动恢复，不需要用户点重试")
    func transientRecovery() async throws {
        var requests = 0
        let expected = challenge()
        let model = AppleSignInPreparation(fetch: {
            requests += 1
            if requests < 3 { throw BackendClientError.transport("offline") }
            return expected
        }, sleep: Self.sleep)
        model.start(monitorNetwork: false)
        defer { model.stop() }
        try await settle { model.state == .ready(expected) }
        #expect(requests == 3)
    }

    @Test("持续断网最多尝试三次，网络恢复后自动重新准备")
    func offlineThenConnected() async throws {
        var requests = 0
        var offline = true
        let expected = challenge()
        let model = AppleSignInPreparation(fetch: {
            requests += 1
            if offline { throw BackendClientError.transport("offline") }
            return expected
        }, sleep: Self.sleep)
        model.start(monitorNetwork: false)
        defer { model.stop() }
        try await settle { model.state == .unavailable(.connection) }
        #expect(requests == 3)
        offline = false
        model.connectionRestored()
        try await settle { model.state == .ready(expected) }
        #expect(requests == 4)
    }

    @Test("永久配置错误不自动重试，服务故障与网络错误分开显示")
    func classifyAndStop() async throws {
        var requests = 0
        let model = AppleSignInPreparation(fetch: {
            requests += 1
            throw BackendClientError.api(code: "DISABLED", message: "", requestID: nil, status: 403)
        }, sleep: Self.sleep)
        model.start(monitorNetwork: false)
        defer { model.stop() }
        try await settle { model.state == .unavailable(.configuration) }
        #expect(requests == 1)
        #expect(AppleSignInPreparation.classify(BackendClientError.api(code: "BUSY", message: "", requestID: nil, status: 503)) == .service)
    }

    @Test("并发恢复不重复请求，授权期间不替换 nonce，取消后获取新凭证")
    func authorizationIsPinned() async throws {
        var requests = 0
        let expected = challenge()
        let model = AppleSignInPreparation(fetch: {
            requests += 1
            await Task.yield()
            return expected
        }, sleep: Self.sleep)
        model.start(monitorNetwork: false)
        defer { model.stop() }
        model.refresh(); model.becameActive(); model.connectionRestored()
        try await settle { model.state == .ready(expected) }
        #expect(requests == 1)
        #expect(model.beginAuthorization() == expected)
        model.refresh(); model.becameActive(); model.connectionRestored()
        #expect(model.state == .authorizing(expected))
        #expect(requests == 1)
        model.authorizationFinished()
        try await settle { requests == 2 && model.state == .ready(expected) }
    }

    @Test("页面关闭后晚到的响应不会恢复按钮或继续重试")
    func cancellation() async throws {
        var continuation: CheckedContinuation<AppleAuthChallenge, Never>?
        let model = AppleSignInPreparation(fetch: {
            await withCheckedContinuation { continuation = $0 }
        }, sleep: Self.sleep)
        model.start(monitorNetwork: false)
        try await settle { continuation != nil }
        model.stop()
        continuation?.resume(returning: challenge())
        try await Task.sleep(for: .milliseconds(10))
        #expect(model.state == .preparing)
    }

    @Test("到期前自动刷新凭证")
    func renewsBeforeExpiry() async throws {
        actor Timer {
            var calls = 0
            func sleep(_ seconds: TimeInterval) async throws {
                calls += 1
                #expect(seconds > 250 && seconds <= 270)
                if calls > 1 { try await Task.sleep(for: .seconds(3600)) }
            }
        }
        let timer = Timer()
        var requests = 0
        let model = AppleSignInPreparation(fetch: {
            requests += 1
            return challenge()
        }, sleep: { try await timer.sleep($0) })
        model.start(monitorNetwork: false)
        defer { model.stop() }
        try await settle { requests == 2 }
        #expect(requests == 2)
    }
    @Test("服务恢复后返回前台自动准备，已就绪时不会多发请求")
    func foregroundRecovery() async throws {
        var requests = 0
        var unavailable = true
        let expected = challenge()
        let model = AppleSignInPreparation(fetch: {
            requests += 1
            if unavailable {
                throw BackendClientError.api(code: "UNAVAILABLE", message: "", requestID: nil, status: 503)
            }
            return expected
        }, sleep: Self.sleep)
        model.start(monitorNetwork: false)
        defer { model.stop() }
        try await settle { model.state == .unavailable(.service) }
        #expect(requests == 3)
        unavailable = false
        model.becameActive()
        try await settle { model.state == .ready(expected) }
        model.becameActive()
        #expect(requests == 4)
    }

}

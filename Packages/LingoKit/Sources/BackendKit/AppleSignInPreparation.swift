import CoreTelephony
import Foundation
import Network
import Observation
import OSLog

/// Owns only the disposable nonce preparation request, never the login exchange.
@MainActor @Observable
public final class AppleSignInPreparation {
    public enum Failure: Equatable {
        case connection, service, configuration
        public var message: String {
            switch self {
            case .connection: "暂时无法连接登录服务，网络恢复后会自动重试"
            case .service: "登录服务暂时繁忙，请稍后重试"
            case .configuration: "登录准备失败，请重试或使用邮箱登录"
            }
        }
    }
    public enum State: Equatable {
        case preparing, ready(AppleAuthChallenge), authorizing(AppleAuthChallenge), unavailable(Failure)
    }
    public private(set) var state: State = .preparing
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var monitor: NWPathMonitor?
    @ObservationIgnored private var cellular: CTCellularData?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var active = false
    @ObservationIgnored private var expiresAt = Date.distantPast
    private let fetch: @MainActor @Sendable () async throws -> AppleAuthChallenge
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private let now: @Sendable () -> Date
    private static let logger = Logger(subsystem: "com.tiantian.lingotrip", category: "AppleSignInPreparation")

    public init(fetch: @escaping @MainActor @Sendable () async throws -> AppleAuthChallenge) {
        self.fetch = fetch
        self.sleep = { try await Task.sleep(for: .seconds($0)) }
        self.now = { Date() }
    }

    // Injected time avoids real network and wall-clock delays in recovery tests.
    init(fetch: @escaping @MainActor @Sendable () async throws -> AppleAuthChallenge,
         sleep: @escaping @Sendable (TimeInterval) async throws -> Void,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.fetch = fetch; self.sleep = sleep; self.now = now
    }

    public func start() { start(monitorNetwork: true) }

    func start(monitorNetwork: Bool) {
        guard !active else { return }
        active = true
        if monitorNetwork {
            let monitor = NWPathMonitor()
            self.monitor = monitor
            monitor.pathUpdateHandler = { [weak self] path in
                guard path.status == .satisfied else { return }
                Task { @MainActor [weak self] in self?.connectionRestored() }
            }
            monitor.start(queue: DispatchQueue(label: "lingotrip.apple-login-connectivity"))
            // First-launch cellular permission can change without changing the network route.
            let cellular = CTCellularData()
            self.cellular = cellular
            cellular.cellularDataRestrictionDidUpdateNotifier = { [weak self] state in
                guard state == .notRestricted else { return }
                Task { @MainActor [weak self] in self?.connectionRestored() }
            }
        }
        refresh()
    }

    public func stop() {
        active = false
        monitor?.cancel(); monitor = nil
        cellular?.cellularDataRestrictionDidUpdateNotifier = nil; cellular = nil
        generation = UUID(); task?.cancel(); task = nil
    }

    public func connectionRestored() {
        guard active, case .unavailable(.connection) = state else { return }
        refresh()
    }

    public func becameActive() {
        guard active else { return }
        switch state {
        case .authorizing: break // Never replace the nonce used by Apple's sheet.
        case .ready where expiresAt > now().addingTimeInterval(30): break
        default: refresh()
        }
    }

    public func refresh() {
        guard active else { return }
        if case .authorizing = state { return }
        if case .preparing = state, task != nil { return }
        task?.cancel()
        let cycle = UUID(); generation = cycle
        state = .preparing
        task = Task { [weak self] in
            guard let self else { return }
            for attempt in 0..<3 {
                do {
                    let requestStarted = now()
                    let challenge = try await fetch()
                    try Task.checkCancellation()
                    guard generation == cycle else { return }
                    let expiry = requestStarted.addingTimeInterval(TimeInterval(challenge.expiresIn))
                    guard expiry > now().addingTimeInterval(30) else { throw BackendClientError.invalidResponse }
                    expiresAt = expiry
                    state = .ready(challenge)
                    // Renew before expiry; cancellation and generation guard protect new requests.
                    try await sleep(max(1, expiry.timeIntervalSince(now()) - 30))
                    try Task.checkCancellation()
                    guard generation == cycle else { return }
                    task = nil
                    refresh()
                    return
                } catch {
                    guard !Task.isCancelled, generation == cycle else { return }
                    let failure = Self.classify(error)
                    Self.logger.notice("Apple challenge attempt \(attempt + 1) failed: \(String(describing: failure), privacy: .public)")
                    if failure != .configuration, attempt < 2 {
                        do { try await sleep(Double(attempt + 1)) }
                        catch { return }
                        guard !Task.isCancelled, generation == cycle else { return }
                    } else {
                        state = .unavailable(failure); task = nil
                        return
                    }
                }
            }
        }
    }

    public func beginAuthorization() -> AppleAuthChallenge? {
        guard case .ready(let challenge) = state, expiresAt > now() else {
            refresh(); return nil
        }
        generation = UUID(); task?.cancel(); task = nil
        state = .authorizing(challenge)
        return challenge
    }

    public func authorizationFinished() {
        state = .preparing
        refresh()
    }

    static func classify(_ error: any Error) -> Failure {
        if error is URLError { return .connection }
        guard let error = error as? BackendClientError else { return .configuration }
        switch error {
        case .transport: return .connection
        case .api(_, _, _, let status) where status == 408 || status == 429 || status >= 500: return .service
        default: return .configuration
        }
    }
}

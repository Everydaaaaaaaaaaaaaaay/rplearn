import Observation
import SwiftUI
import Translation

/// Bridges SwiftUI's system-owned translation session into an on-demand local API.
///
/// 只用本机已安装的语言包翻译，翻译过程中绝不弹系统窗口。语言包没装时 `translate` 直接返回 nil，
/// 由页面给出“下载 / 改用 AI”的选择；只有用户点了下载（`requestDownload`），才调用
/// `prepareTranslation()` 让系统弹出下载确认。语言资源由系统下载，从不随包附带。
@MainActor
@Observable
public final class AppleTranslator {
    public enum Availability: Equatable, Sendable {
        /// 还没查到本机状态。
        case checking
        /// 语言包已在本机，可以直接翻译。
        case installed
        /// 支持这对语言，但需要先下载语言包。
        case downloadable
        /// 用户已同意下载，系统正在处理。
        case downloading
        /// 本机不支持这对语言的离线翻译（例如模拟器）。
        case unsupported
    }

    public internal(set) var availability: Availability = .checking
    public private(set) var configuration: TranslationSession.Configuration?
    private(set) var sessionID = UUID()
    private var isSessionRunning = false
    private var downloadRequested = false
    private var pending: [UUID: CheckedContinuation<String?, Never>] = [:]
    private var inbox: [(id: UUID, text: String)] = []
    private var deadlines: [UUID: Task<Void, Never>] = [:]

    private let requestTimeout: Duration
    private let sourceLanguage: String
    private let targetLanguage: String

    public init(sourceLanguage: String = "en", targetLanguage: String = "zh-Hans", requestTimeout: Duration = .seconds(120)) {
        self.requestTimeout = requestTimeout
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
    }

    /// 查询本机语言包状态，不会弹出任何界面。下载进行中时保持“下载中”。
    @discardableResult
    public func refreshAvailability() async -> Availability {
        #if targetEnvironment(simulator)
        // Apple's translation models are unavailable in Simulator.
        availability = .unsupported
        #else
        guard availability != .downloading else { return availability }
        let status = await LanguageAvailability().status(
            from: Locale.Language(identifier: sourceLanguage),
            to: Locale.Language(identifier: targetLanguage)
        )
        guard availability != .downloading else { return availability }
        availability = Self.availability(for: status)
        #endif
        return availability
    }

    nonisolated static func availability(for status: LanguageAvailability.Status) -> Availability {
        switch status {
        case .installed: .installed
        case .supported: .downloadable
        case .unsupported: .unsupported
        @unknown default: .unsupported
        }
    }

    /// 用户点“下载”后调用：由系统弹出下载确认，结束（完成或拒绝）后重新检查。
    public func requestDownload() {
        guard availability == .downloadable else { return }
        availability = .downloading
        downloadRequested = true
        triggerSession()
    }

    /// 只在语言包已安装时翻译；未安装、不支持或失败时返回 nil，从不弹出下载窗口。
    public func translate(_ text: String) async -> String? {
        #if targetEnvironment(simulator)
        return nil
        #else
        if availability == .checking { await refreshAvailability() }
        guard availability == .installed else { return nil }
        return await enqueue(text)
        #endif
    }

    func enqueue(_ text: String) async -> String? {
        guard !Task.isCancelled, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(returning: nil); return }
                pending[id] = continuation
                inbox.append((id, text))
                triggerSession()
                deadlines[id] = Task { @MainActor in
                    do { try await Task.sleep(for: requestTimeout) }
                    catch { return }
                    cancelRequest(id)
                }
            }
        } onCancel: {
            Task { @MainActor in self.cancelRequest(id) }
        }
    }

    func takeDownloadRequest() -> Bool {
        defer { downloadRequested = false }
        return downloadRequested
    }

    func downloadFinished() async {
        availability = .checking
        await refreshAvailability()
    }

    func takeBatch(sessionID: UUID) -> [(id: UUID, text: String)] {
        guard self.sessionID == sessionID else { return [] }
        let batch = inbox
        inbox.removeAll()
        return batch
    }

    func complete(_ id: UUID, with value: String?) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        inbox.removeAll { $0.id == id }
        deadlines.removeValue(forKey: id)?.cancel()
        continuation.resume(returning: value)
    }

    func finishSession(_ id: UUID, failed: Bool = false) {
        guard sessionID == id else { return }
        isSessionRunning = false
        if failed {
            for requestID in Array(pending.keys) { complete(requestID, with: nil) }
            // 已安装的语言包可能被删掉：重新确认，避免之后每次都空等。
            Task { await refreshAvailability() }
        }
        if !inbox.isEmpty || downloadRequested { triggerSession() }
    }

    /// 放弃所有等待中的翻译。系统下载进行中时保留会话，继续打字或切换模式不会打断下载。
    func cancelAll() {
        for id in Array(pending.keys) { complete(id, with: nil) }
        inbox.removeAll()
        guard availability != .downloading else { return }
        sessionID = UUID()
        configuration = nil
        isSessionRunning = false
    }

    private func cancelRequest(_ id: UUID) {
        guard pending[id] != nil else { return }
        complete(id, with: nil)
        // A stalled/abandoned session must not trap later retries behind it.
        if pending.isEmpty { cancelAll() }
    }

    private func triggerSession() {
        // New requests join the active session instead of invalidating each other.
        guard !isSessionRunning else { return }
        isSessionRunning = true
        sessionID = UUID()
        if configuration == nil {
            configuration = TranslationSession.Configuration(
                source: Locale.Language(identifier: sourceLanguage),
                target: Locale.Language(identifier: targetLanguage)
            )
        } else {
            configuration?.invalidate()
        }
    }
}

/// Each direction gets an independent stable host, outside the resizing input bar.
/// Capture the generation before launching, so a late old task cannot take a new queue.
struct AppleTranslationHost: View {
    let translator: AppleTranslator

    var body: some View {
        let generation = translator.sessionID
        Color.clear
            .frame(width: 1, height: 1)
            .translationTask(translator.configuration) { @Sendable session in
                var failed = false
                // 只有用户点了“下载”才请求系统下载确认；平时语言包已安装，直接翻译不弹窗。
                if await translator.takeDownloadRequest() {
                    try? await session.prepareTranslation()
                    await translator.downloadFinished()
                }
                do {
                    while !Task.isCancelled {
                        let batch = await translator.takeBatch(sessionID: generation)
                        if batch.isEmpty { break }
                        for item in batch {
                            try Task.checkCancellation()
                            let result = try? await session.translate(item.text).targetText
                            await translator.complete(item.id, with: result)
                        }
                    }
                } catch { failed = true }
                await translator.finishSession(generation, failed: failed || Task.isCancelled)
            }
            .id(generation)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

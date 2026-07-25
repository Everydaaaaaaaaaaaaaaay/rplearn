import Observation
import SwiftUI
import Translation

/// Apple 端上翻译（Translation 框架）封装为可按需调用的 async 接口。
///
/// `TranslationSession` 只能由 SwiftUI 的 `.translationTask` 修饰器提供、无法独立构造，
/// 故这里用「配置触发 + 请求队列 + 续体」把它桥接成 `translate(_:) async -> String?`，
/// 作为云端 LLM 翻译在离线/失败时的兜底。语言包首次使用需联网下载（系统弹窗）。
@MainActor
@Observable
public final class AppleTranslator {
    /// 绑定到 `.translationTask`；nil→非 nil 启动会话，`invalidate()` 触发重跑。
    public private(set) var configuration: TranslationSession.Configuration?

    private var pending: [UUID: CheckedContinuation<String?, Never>] = [:]
    private var inbox: [(id: UUID, text: String)] = []

    public init() {}

    /// 把英文译成简体中文；语言包不可用或失败时返回 nil（含 20s 超时兜底，避免卡死）。
    public func translate(_ text: String) async -> String? {
        let id = UUID()
        return await withCheckedContinuation { continuation in
            pending[id] = continuation
            inbox.append((id, text))
            triggerSession()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(20))
                complete(id, with: nil)
            }
        }
    }

    /// 取走并清空当前待翻译批次（由 `.translationTask` 闭包驱动）。
    /// session 非 Sendable 只能在闭包内内联使用，故这里只交换纯数据。
    func takeBatch() -> [(id: UUID, text: String)] {
        let batch = inbox
        inbox.removeAll()
        return batch
    }

    /// 回填一条翻译结果（供 `.translationTask` 闭包调用）。
    func complete(_ id: UUID, with value: String?) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        continuation.resume(returning: value)
    }

    private func triggerSession() {
        if configuration == nil {
            configuration = TranslationSession.Configuration(
                source: Locale.Language(identifier: "en"),
                target: Locale.Language(identifier: "zh-Hans")
            )
        } else {
            // 会话已存在：使其失效以让 .translationTask 用新 session 重跑。
            configuration?.invalidate()
        }
    }
}

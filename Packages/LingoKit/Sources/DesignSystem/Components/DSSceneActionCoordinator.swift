import SwiftUI

/// 摄影场景入口共同使用的压感外观与弹簧参数。
public enum DSSceneEntranceMotion {
    public static let pressedScale: CGFloat = 0.90
    public static let pressedOffset: CGFloat = 2.5
    public static let pressedBrightness = 0.11
    public static let pressedOpacity = 0.93
    public static let pressResponse = 0.18
    public static let pressDampingFraction = 0.82
    public static let releaseDuration = 0.08
    public static let releaseBounce = 0.16
}

/// 摄影场景入口共享的“按下—保持—回弹—提交”时序。
///
/// 首页与“我的”页共同读取这一份状态机，避免轻点反馈、回弹完成时刻和页面提交时刻漂移。
@MainActor
public final class DSSceneActionCoordinator<Hotspot: Hashable>: ObservableObject {
    public static var pressedHoldDuration: Duration { .milliseconds(20) }
    public static var reboundDuration: Duration { .milliseconds(80) }
    public static var postReboundDelay: Duration { .milliseconds(20) }

    @Published public private(set) var pressedHotspot: Hotspot?
    private var pendingAction: Task<Void, Never>?

    public init() {}

    public func perform(
        for hotspot: Hotspot,
        action: @escaping @MainActor () -> Void
    ) {
        guard pendingAction == nil else { return }

        pressedHotspot = hotspot
        pendingAction = Task { @MainActor in
            do {
                try await Task.sleep(for: Self.pressedHoldDuration)
                pressedHotspot = nil
                try await Task.sleep(for: Self.reboundDuration)
                try await Task.sleep(for: Self.postReboundDelay)
                guard !Task.isCancelled else { return }
                pendingAction = nil
                action()
            } catch {
                pressedHotspot = nil
                pendingAction = nil
            }
        }
    }

    public func cancel() {
        pendingAction?.cancel()
        pendingAction = nil
        pressedHotspot = nil
    }
}

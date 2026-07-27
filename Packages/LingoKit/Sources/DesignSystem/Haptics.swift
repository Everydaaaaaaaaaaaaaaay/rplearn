#if canImport(UIKit)
import UIKit

/// 触觉反馈统一入口，全部在主线程执行。
@MainActor
public enum Haptics {
    /// 轻/中/重碰撞——用于发送、点选、进入等一般动作。
    public static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    /// 成功/警告/失败——用于答对答错、加好友、出行等结果反馈。
    public static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }

    /// 选择变化——用于切换 Tab/选项等。
    public static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
#else
public enum Haptics {
    public enum Dummy { case light }
    public static func impact(_ style: Dummy = .light) {}
    public static func selection() {}
}
#endif

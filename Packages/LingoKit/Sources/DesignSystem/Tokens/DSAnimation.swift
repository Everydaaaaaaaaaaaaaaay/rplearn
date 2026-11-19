import SwiftUI

public enum DSAnimation {
    /// 高频点击反馈保持短促，使用零回弹临界阻尼弹簧，立即起步并平滑落定。
    public static let feedback = Animation.snappy(duration: 0.16, extraBounce: 0)
    /// 小范围状态切换、浮窗与面板展开，立即响应、可中途打断。
    public static let snappy = Animation.snappy(duration: 0.22, extraBounce: 0)
    /// 跟手拖拽松手回弹与抽屉交互。
    public static let interactive = Animation.interactiveSpring(duration: 0.28, extraBounce: 0)
    /// 场景或大块内容切换，强调空间连续性与自然减速。
    public static let scene = Animation.smooth(duration: 0.34, extraBounce: 0)
    /// 只用于低频奖励、选角确认等庆祝时刻。
    public static let celebration = Animation.spring(duration: 0.42, bounce: 0.16)

    /// 减弱动态效果时统一降级为短促柔和淡化。
    public static func resolve(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.14) : animation
    }
}

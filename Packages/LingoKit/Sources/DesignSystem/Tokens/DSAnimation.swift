import SwiftUI

public enum DSAnimation {
    /// 高频点击反馈保持短促，不使用弹跳。
    public static let feedback = Animation.easeOut(duration: 0.12)
    /// 小范围状态切换，立即响应并快速收束。
    public static let snappy = Animation.easeOut(duration: 0.18)
    /// 场景或大块内容切换，强调空间连续性。
    public static let scene = Animation.easeInOut(duration: 0.32)
    /// 只用于低频奖励、选角确认等庆祝时刻。
    public static let celebration = Animation.spring(duration: 0.38, bounce: 0.14)
}

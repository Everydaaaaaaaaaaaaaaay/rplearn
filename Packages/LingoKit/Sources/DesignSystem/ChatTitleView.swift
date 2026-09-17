import SwiftUI

/// 正式聊天与本地开场共用的导航标题，不依赖会话或网络服务。
public struct ChatTitleView<Avatar: View>: View {
    private let title: String
    private let subtitle: String
    private let avatar: Avatar

    public init(title: String, subtitle: String, @ViewBuilder avatar: () -> Avatar) {
        self.title = title
        self.subtitle = subtitle
        self.avatar = avatar()
    }

    public var body: some View {
        HStack(spacing: 8) {
            avatar
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .allowsTightening(true)
                    // 状态文案长度不同（例如「刚刚在线 · 城市 12:19」），
                    // 缩小而不是截断，保证城市和当地时间始终可见。
                    .minimumScaleFactor(0.6)
            }
            .layoutPriority(1)
        }
        .accessibilityElement(children: .combine)
    }
}

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
                Text(title).font(.subheadline.bold())
                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

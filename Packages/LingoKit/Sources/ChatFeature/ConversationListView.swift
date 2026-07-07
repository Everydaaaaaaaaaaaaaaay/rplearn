import SwiftUI

/// 消息 tab：会话列表，进入各角色聊天页；收藏夹入口。
/// 后续单元逐步填充，当前为占位。
public struct ConversationListView: View {
    public init() {}

    public var body: some View {
        ContentUnavailableView(
            "消息",
            systemImage: "bubble.left.and.bubble.right",
            description: Text("与 AI 角色的会话将显示在这里")
        )
        .navigationTitle("消息")
    }
}

#Preview {
    NavigationStack {
        ConversationListView()
    }
}

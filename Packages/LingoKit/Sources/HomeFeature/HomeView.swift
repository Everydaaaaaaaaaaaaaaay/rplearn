import SwiftUI

/// 主页 hub：当前地区卡片、开展活动入口、地图/剧情/票根夹入口、主线提示。
/// 后续单元逐步填充，当前为占位。
public struct HomeView: View {
    public init() {}

    public var body: some View {
        ContentUnavailableView(
            "主页",
            systemImage: "house",
            description: Text("当前地区、活动与主线入口即将上线")
        )
        .navigationTitle("主页")
    }
}

#Preview {
    NavigationStack {
        HomeView()
    }
}

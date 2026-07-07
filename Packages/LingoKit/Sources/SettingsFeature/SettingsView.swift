import SwiftUI

/// 设置 tab：LLM 供应商配置、出题开关、订阅调试面板等。
/// 后续单元逐步填充，当前为占位。
public struct SettingsView: View {
    public init() {}

    public var body: some View {
        ContentUnavailableView(
            "设置",
            systemImage: "gearshape",
            description: Text("供应商与偏好设置即将上线")
        )
        .navigationTitle("设置")
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}

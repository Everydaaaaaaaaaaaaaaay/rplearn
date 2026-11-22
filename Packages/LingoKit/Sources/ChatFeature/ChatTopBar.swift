import DesignSystem
import SwiftUI

extension View {
    /// 把聊天页顶栏放在页面顶部的安全区里。iOS 26 起用 `safeAreaBar`，消息滚到顶栏下方时有系统的柔和模糊；
    /// 更早的系统用一层白色渐隐托底。
    @ViewBuilder
    func chatTopBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        if #available(iOS 26.0, *) {
            safeAreaBar(edge: .top, spacing: 0, content: bar)
        } else {
            safeAreaInset(edge: .top, spacing: 0) {
                bar().background {
                    LinearGradient(colors: [Puff.Palette.page, Puff.Palette.page.opacity(0)],
                                   startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea(edges: .top)
                }
            }
        }
    }
}

/// 顶栏上的白色软胶囊：细边 + 轻影，放一个或一组图标按钮。
struct ChatTopBarChip<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .background(Puff.Palette.card, in: Capsule())
            .overlay { Capsule().strokeBorder(Puff.Palette.line, lineWidth: 1) }
            .shadow(color: Puff.Palette.ink.opacity(0.06), radius: 6, y: 2)
    }
}

/// 顶栏图标：44pt 触控区，墨色圆体线条。
struct ChatTopBarIcon: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: Puff.Weight.icon, design: .rounded))
            .foregroundStyle(Puff.Palette.ink)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
    }
}

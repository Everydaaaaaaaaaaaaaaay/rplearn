import SwiftUI

/// 系统表单与列表的蓬蓬外观：浅云色底、圆角分组、圆体字，行内图标放进糖果色小气泡。
/// 只改外观，开关、菜单、左滑操作、无障碍等仍是系统表单的行为。
private struct PuffFormStyle: ViewModifier {
    let candy: PuffCandy

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(Puff.Palette.cloud.ignoresSafeArea())
            .fontDesign(.rounded)
            .tint(candy.deep)
            .labelStyle(PuffBubbleLabelStyle(candy: candy))
            .environment(\.defaultMinListRowHeight, 50)
    }
}

/// 图标放进圆角糖果色气泡的标签样式；标题颜色沿用环境（破坏性操作仍是红色）。
public struct PuffBubbleLabelStyle: LabelStyle {
    private let candy: PuffCandy

    public init(candy: PuffCandy = .sky) {
        self.candy = candy
    }

    public func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.icon
                .font(.system(size: 14, weight: Puff.Weight.icon, design: .rounded))
                .foregroundStyle(candy.deep)
                .frame(width: 30, height: 30)
                .background(candy.wash, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)
            configuration.title
        }
    }
}

public extension View {
    /// 用在 `Form` / `List` 上，让系统表单页与蓬蓬页面一致。
    func puffFormStyle(candy: PuffCandy = .sky) -> some View {
        modifier(PuffFormStyle(candy: candy))
    }
}

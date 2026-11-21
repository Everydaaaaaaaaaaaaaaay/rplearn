import DesignSystem
import SwiftUI

/// 蓬蓬输入面板：白色圆顶卡片，打开翻译器时染上淡淡的葡萄紫。
struct ComposerPanelSurface: View {
    let expanded: Bool
    private let shape = UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)

    var body: some View {
        ZStack {
            Puff.Palette.card
            if expanded { PuffCandy.grape.wash.opacity(0.7) }
        }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(expanded ? PuffCandy.grape.base.opacity(0.35) : Puff.Palette.line, lineWidth: 1.5)
                .mask(alignment: .top) {
                    LinearGradient(colors: [.white, .white, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 40)
                }
        }
        .shadow(color: Color.black.opacity(0.04), radius: 10, y: -4)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct ComposerModeSwitch: View {
    @Binding var mode: ComposerTranslationModel.Mode
    @Namespace private var selection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 2) {
            ForEach(ComposerTranslationModel.Mode.allCases, id: \.self) { item in
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.95)) { mode = item }
                } label: {
                    Text(item.rawValue).font(.puff(.subheadline, Puff.Weight.emphasis))
                        .foregroundStyle(mode == item ? Color.white : Puff.Palette.inkSoft)
                        .frame(maxWidth: .infinity).frame(height: 30)
                        .background {
                            if mode == item {
                                Capsule().fill(PuffCandy.grape.base)
                                    .matchedGeometryEffect(id: "selection", in: selection)
                            }
                        }
                }
                .buttonStyle(.puffSquish)
                .accessibilityAddTraits(mode == item ? .isSelected : [])
            }
        }
        .padding(3).frame(width: 170)
        .background(Puff.Palette.cloud, in: Capsule())
    }
}

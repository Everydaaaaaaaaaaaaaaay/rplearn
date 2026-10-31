import DesignSystem
import SwiftUI

/// Quiet, static mascot palettes. The composer owns its layout and transition.
struct ComposerPanelSurface: View {
    let expanded: Bool
    var body: some View {
        DSReadingPalette.paper
            .overlay(alignment: .top) { DSReadingPalette.line.frame(height: 0.5) }
            .allowsHitTesting(false).accessibilityHidden(true)
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
                    Text(item.rawValue).font(.subheadline.weight(.semibold))
                        .foregroundStyle(mode == item ? DSReadingPalette.onPrimary : DSReadingPalette.secondary)
                        .frame(maxWidth: .infinity).frame(height: 30)
                        .background {
                            if mode == item {
                                Capsule().fill(DSReadingPalette.primary)
                                    .matchedGeometryEffect(id: "selection", in: selection)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(mode == item ? .isSelected : [])
            }
        }
        .padding(3).frame(width: 170)
        .background(DSReadingPalette.canvas, in: Capsule())
        .overlay(Capsule().strokeBorder(DSReadingPalette.line, lineWidth: 1))
    }
}

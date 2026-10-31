import SwiftUI

/// Quiet, static mascot palettes. The composer owns its layout and transition.
struct ComposerPanelSurface: View {
    let expanded: Bool
    @Environment(\.colorScheme) private var scheme
    private var accent: Color {
        expanded ? Color(red: 0.58, green: 0.45, blue: 0.87)
                 : Color(red: 0.24, green: 0.65, blue: 0.90)
    }
    private let shape = UnevenRoundedRectangle(topLeadingRadius: 25, topTrailingRadius: 25)

    var body: some View {
        ZStack {
            (scheme == .dark ? Color(red: 0.10, green: 0.11, blue: 0.14) : Color.white)
            // Gugu: airy sky blue. Gaga: soft lilac. No waterline or moving texture.
            LinearGradient(colors: [accent.opacity(scheme == .dark ? 0.15 : 0.06),
                                    accent.opacity(scheme == .dark ? 0.10 : 0.13)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .clipShape(shape)
        .overlay {
            ZStack {
                shape.strokeBorder(accent.opacity(scheme == .dark ? 0.30 : 0.22), lineWidth: 1)
                shape.inset(by: 2).strokeBorder(
                    LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.13 : 0.90), .clear],
                                   startPoint: .top, endPoint: .bottom), lineWidth: 3)
                shape.inset(by: 5).strokeBorder(accent.opacity(0.07), lineWidth: 0.5)
            }
            .mask(alignment: .top) {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.white, .white, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 32)
                    Spacer(minLength: 0)
                }
            }
        }
        .shadow(color: accent.opacity(scheme == .dark ? 0.05 : 0.08), radius: 8, y: -3)
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
                    Text(item.rawValue).font(.subheadline.weight(.semibold))
                        .foregroundStyle(mode == item ? Color.white : Color.secondary)
                        .frame(maxWidth: .infinity).frame(height: 30)
                        .background {
                            if mode == item {
                                Capsule().fill(Color(red: 0.53, green: 0.40, blue: 0.94))
                                    .matchedGeometryEffect(id: "selection", in: selection)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(mode == item ? .isSelected : [])
            }
        }
        .padding(3).frame(width: 170)
        .background(.thinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.purple.opacity(0.12), lineWidth: 1))
    }
}

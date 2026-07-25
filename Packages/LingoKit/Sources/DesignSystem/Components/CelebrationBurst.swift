import SwiftUI

private struct CelebrationModifier: ViewModifier {
    let active: Bool
    let tint: Color
    let trigger: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if active, visible {
                    ZStack {
                        ForEach(0..<14, id: \.self) { index in
                            Group {
                                if index.isMultiple(of: 3) {
                                    Image(systemName: "sparkle")
                                } else {
                                    Circle()
                                }
                            }
                            .foregroundStyle(particleColor(index))
                            .frame(width: 8, height: 8)
                            .offset(particleOffset(index))
                            .rotationEffect(.degrees(expanded ? Double(index * 42) : 0))
                            .opacity(expanded ? 0 : 1)
                        }
                    }
                    .allowsHitTesting(false)
                }
            }
            .onAppear {
                if trigger != 0 { burst() }
            }
            .onChange(of: trigger) { burst() }
    }

    private func particleColor(_ index: Int) -> Color {
        switch index % 3 {
        case 0: tint
        case 1: .dsSunset
        default: .dsSuccess
        }
    }

    private func particleOffset(_ index: Int) -> CGSize {
        guard expanded, !reduceMotion else { return .zero }
        let angle = Double(index) / 14 * .pi * 2
        let distance = CGFloat(42 + (index % 4) * 9)
        return CGSize(width: cos(angle) * distance, height: sin(angle) * distance)
    }

    private func burst() {
        guard active else { return }
        expanded = false
        visible = true
        withAnimation(reduceMotion ? .easeOut(duration: 0.4) : .spring(duration: 0.8, bounce: 0.15)) {
            expanded = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 450 : 850))
            visible = false
        }
    }
}

public extension View {
    func celebration(_ active: Bool = true, tint: Color = .dsSky, trigger: Int) -> some View {
        modifier(CelebrationModifier(active: active, tint: tint, trigger: trigger))
    }
}

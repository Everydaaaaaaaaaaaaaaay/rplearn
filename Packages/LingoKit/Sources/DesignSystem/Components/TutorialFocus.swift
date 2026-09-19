import SwiftUI

public struct TutorialTargetPreference: PreferenceKey {
    public static var defaultValue: [String: Anchor<CGRect>] { [:] }
    public static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct TutorialFocusModifier: ViewModifier {
    let id: String
    let active: Bool
    let padding: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glowing = false
    func body(content: Content) -> some View {
        content
            .anchorPreference(key: TutorialTargetPreference.self, value: .bounds) { active ? [id: $0] : [:] }
            .overlay {
                if active {
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Color.dsSkyDeep.opacity(glowing ? 0.85 : 0.3), lineWidth: 2)
                        .shadow(color: Color.dsSkyDeep.opacity(glowing ? 0.3 : 0.05), radius: glowing ? 10 : 3)
                        .padding(-padding).allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .task(id: active && !reduceMotion) {
                guard active, !reduceMotion else { glowing = false; return }
                withAnimation(.easeInOut(duration: 1.25).repeatForever(autoreverses: true)) { glowing = true }
            }
    }
}

public extension View {
    func tutorialFocus(_ id: String, active: Bool, padding: CGFloat = 3) -> some View {
        modifier(TutorialFocusModifier(id: id, active: active, padding: padding))
    }
}

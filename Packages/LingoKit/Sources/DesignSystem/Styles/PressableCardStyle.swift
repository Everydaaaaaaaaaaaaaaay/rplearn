import SwiftUI

public struct PressableCardStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.985)
            .opacity(configuration.isPressed ? 0.94 : 1)
            .animation(reduceMotion ? nil : DSAnimation.feedback, value: configuration.isPressed)
    }
}

public extension ButtonStyle where Self == PressableCardStyle {
    static var pressableCard: PressableCardStyle { PressableCardStyle() }
}

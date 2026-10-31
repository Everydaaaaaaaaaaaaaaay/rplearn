import SwiftUI

public enum DSWorkbenchSceneFocus: Sendable, Equatable {
    case learning, favorites, settings, account, archive, profile, subscription
}

/// Functional screens share the reading palette; photographic scenes belong to their Feature.
public struct DSWorkbenchBackdrop: View {
    public init(focus: DSWorkbenchSceneFocus) {}
    public var body: some View {
        DSReadingPalette.canvas.ignoresSafeArea().accessibilityHidden(true).allowsHitTesting(false)
    }
}

public enum DSWorkbenchPanelWeight: Sendable, Equatable { case chrome, content, reading }

/// Compatibility API for existing functional panels, rendered with the shared paper component.
public struct DSWorkbenchPanel<Content: View>: View {
    private let content: Content
    private let padding: CGFloat
    private let weight: DSWorkbenchPanelWeight
    public init(weight: DSWorkbenchPanelWeight = .content, radius: CGFloat = DSRadius.card,
                padding: CGFloat = DSSpacing.lg, @ViewBuilder content: () -> Content) {
        self.content = content(); self.padding = padding; self.weight = weight
    }
    public var body: some View { DSPaper(padding: padding, floating: weight == .reading) { content } }
}

public struct DSWorkbenchPaperSheet<Content: View>: View {
    private let content: Content
    private let padding: CGFloat
    public init(radius: CGFloat = DSRadius.card, padding: CGFloat = DSSpacing.lg,
                @ViewBuilder content: () -> Content) {
        self.content = content(); self.padding = padding
    }
    public var body: some View { DSPaper(padding: padding) { content } }
}

/// Existing callers retain their layout size while using the same plain SF Symbols as other pages.
public struct DSObsidianMedallion: View {
    private let symbol: String
    private let size: CGFloat
    public init(systemImage: String, size: CGFloat = 64, isRaised: Bool = true) {
        self.symbol = systemImage; self.size = size
    }
    public var body: some View {
        Image(systemName: symbol).font(.system(size: min(size * 0.4, 26), weight: .regular))
            .foregroundStyle(DSReadingPalette.tint).frame(width: size, height: size).accessibilityHidden(true)
    }
}

public struct DSWorkbenchActionButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        DSActionButtonStyle().makeBody(configuration: configuration)
    }
}

public extension ButtonStyle where Self == DSWorkbenchActionButtonStyle {
    static var dsWorkbenchAction: DSWorkbenchActionButtonStyle { DSWorkbenchActionButtonStyle() }
}

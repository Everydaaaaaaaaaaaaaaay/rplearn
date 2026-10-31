import SwiftUI

public struct DSPaper<Content: View>: View {
    private let padding: CGFloat
    private let floating: Bool
    private let content: Content
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    public init(padding: CGFloat = 20, floating: Bool = false, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.floating = floating
        self.content = content()
    }

    public var body: some View {
        content.padding(padding)
            .background(DSReadingPalette.paper.opacity(floating && !reduceTransparency ? 0.95 : 1),
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(DSReadingPalette.line.opacity(contrast == .increased ? 1 : 0.55),
                            lineWidth: contrast == .increased ? 1 : 0.5)
            }
            .shadow(color: .black.opacity(floating ? 0.12 : 0), radius: 12, y: 5)
    }
}

public struct DSReadingChoice: View {
    private let english: String
    private let chinese: String?
    private let action: () -> Void

    public init(english: String, chinese: String? = nil, action: @escaping () -> Void) {
        self.english = english
        self.chinese = chinese
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: "arrow.up.right").font(.caption)
                    .foregroundStyle(DSReadingPalette.gold).padding(.top, 3)
                VStack(alignment: .leading, spacing: 5) {
                    Text(english).font(.subheadline.weight(.medium)).foregroundStyle(DSReadingPalette.ink)
                    if let chinese { Text(chinese).font(.caption).foregroundStyle(DSReadingPalette.secondary) }
                }
                Spacer(minLength: 0)
            }.padding(13).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .background(DSReadingPalette.ink.opacity(0.035), in: RoundedRectangle(cornerRadius: 6))
                .overlay { RoundedRectangle(cornerRadius: 6).stroke(DSReadingPalette.gold.opacity(0.45), lineWidth: 0.7) }
        }.buttonStyle(DSReadingPressStyle())
    }
}

public struct DSReadingPressStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(!enabled ? 0.4 : configuration.isPressed ? 0.65 : 1)
    }
}

public struct DSReadingRow: View {
    private let title: String
    private let symbol: String
    private let value: String?
    public init(_ title: String, symbol: String, value: String? = nil) {
        self.title = title; self.symbol = symbol; self.value = value
    }
    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 18)).frame(width: 23).foregroundStyle(DSReadingPalette.tint)
            Text(title).font(.body).foregroundStyle(DSReadingPalette.ink)
            Spacer(minLength: 8)
            if let value { Text(value).font(.subheadline).foregroundStyle(DSReadingPalette.secondary).multilineTextAlignment(.trailing) }
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(DSReadingPalette.secondary.opacity(0.7))
        }.frame(minHeight: 51).contentShape(Rectangle())
    }
}

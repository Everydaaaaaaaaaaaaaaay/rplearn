import SwiftUI

/// A quiet, shared affordance for tap-to-advance stories.
public struct TapToContinueHint: View {
    private let showsTranslation: Bool
    public init(showsTranslation: Bool = false) { self.showsTranslation = showsTranslation }
    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.tap").font(.caption)
            Text("Tap to continue").font(.caption)
            if showsTranslation { Text("轻点空白继续").font(.caption2) }
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity).frame(minHeight: 44)
    }
}

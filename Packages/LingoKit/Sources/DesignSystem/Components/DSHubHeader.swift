import SwiftUI

public struct DSHubHeader: View {
    private let title: String
    private let symbol: String?
    private let actionLabel: String?
    private let action: (() -> Void)?

    public init(title: String, symbol: String? = nil, actionLabel: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.symbol = symbol
        self.actionLabel = actionLabel
        self.action = action
    }

    public var body: some View {
        HStack {
            Color.clear.frame(width: 44, height: 44)
            Text(title).font(.headline).frame(maxWidth: .infinity)
            if let symbol, let action {
                Button(action: action) {
                    Image(systemName: symbol).font(.system(size: 21, weight: .regular))
                        .frame(width: 44, height: 44)
                        .dsSceneGlass(radius: 22, interactive: true)
                }
                .buttonStyle(.plain).accessibilityLabel(actionLabel ?? title)
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .foregroundStyle(Color.dsSceneTextPrimary)
        .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 12)
        .background {
            Rectangle().fill(.regularMaterial)
                .mask {
                    LinearGradient(stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.72),
                        .init(color: .clear, location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                }
                .ignoresSafeArea(edges: .top)
        }
    }
}

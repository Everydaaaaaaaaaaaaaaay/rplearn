import SwiftUI

/// 让内容浮在城市摄影上，同时为导航栏和底部 Tab 保留稳定的可读性。
public struct DSSceneBackdrop: View {
    public enum Tone: Sendable {
        case cool
        case warm
    }

    private let imageName: String
    private let tone: Tone

    public init(imageName: String, tone: Tone) {
        self.imageName = imageName
        self.tone = tone
    }

    public var body: some View {
        GeometryReader { proxy in
            Image(imageName)
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .overlay { atmosphericWash }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var atmosphericWash: some View {
        LinearGradient(
            stops: [
                .init(color: topWash, location: 0),
                .init(color: middleWash, location: 0.42),
                .init(color: bottomWash, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var topWash: Color {
        switch tone {
        case .cool: .black.opacity(0.22)
        case .warm: .white.opacity(0.17)
        }
    }

    private var middleWash: Color {
        switch tone {
        case .cool: .black.opacity(0.08)
        case .warm: .white.opacity(0.06)
        }
    }

    private var bottomWash: Color {
        switch tone {
        case .cool: .black.opacity(0.28)
        case .warm: .black.opacity(0.12)
        }
    }
}

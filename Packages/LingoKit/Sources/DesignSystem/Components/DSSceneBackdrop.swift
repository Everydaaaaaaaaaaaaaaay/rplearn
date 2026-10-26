import SwiftUI

public enum DSCitySceneRole: String, Sendable {
    case messages
    case contacts
    case learning
}

/// 将当前旅程地区映射到已核验的城市摄影；学习页复用信息页地标摄影，避免重复入包。
public enum DSCitySceneAssets {
    public static let supportedRegionIDs: Set<String> = [
        "auckland",
        "capetown",
        "dublin",
        "edinburgh",
        "kingston",
        "london",
        "manchester",
        "melbourne",
        "nairobi",
        "neworleans",
        "newyork",
        "singapore",
        "sydney",
        "toronto",
        "vancouver",
    ]

    public static func imageName(
        for role: DSCitySceneRole,
        regionID: String?
    ) -> String {
        let normalizedRegionID = regionID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let resolvedRegionID = normalizedRegionID.flatMap { regionID in
            supportedRegionIDs.contains(regionID) ? regionID : nil
        } ?? "london"
        let assetRole = role == .learning ? DSCitySceneRole.messages : role
        return "\(assetRole.rawValue)_\(resolvedRegionID)_glass"
    }
}

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

/// 以整张场景为一个平面，避免入口和背景在透视变化时错位。
struct DSSceneDragPose {
    let offset: CGSize
    let pitch: Double
    let yaw: Double
    let scale: CGFloat

    static func resolve(translation: CGSize, viewport: CGSize) -> Self {
        let distance = hypot(translation.width, translation.height)
        let limit: CGFloat = 8
        // 小幅跟手，越拉越紧；斜向拖动同样受总距离限制。
        let resisted = limit * (distance * 0.10) / (limit + distance * 0.10)
        let ratio = distance > 0 ? resisted / distance : 0
        let offset = CGSize(width: translation.width * ratio, height: translation.height * ratio)
        let amount = resisted / limit
        // 随位移增加覆盖余量，静止时保持原图构图；透视和回弹都留有边缘余量。
        let coverage = max(abs(offset.width) / max(viewport.width, 1), abs(offset.height) / max(viewport.height, 1))
        return Self(
            offset: offset,
            pitch: Double(-offset.height / limit) * 0.5,
            yaw: Double(offset.width / limit) * 0.5,
            scale: 1 + coverage * 2.6 + amount * 0.006
        )
    }
}

private struct DSSceneDragMotion: ViewModifier {
    let viewport: CGSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState(resetTransaction: Transaction(animation: .spring(response: 0.32, dampingFraction: 0.88)))
    private var translation = CGSize.zero

    func body(content: Content) -> some View {
        let pose = DSSceneDragPose.resolve(translation: reduceMotion ? .zero : translation, viewport: viewport)
        content
            .scaleEffect(pose.scale)
            .rotation3DEffect(.degrees(pose.pitch), axis: (x: 1, y: 0, z: 0), perspective: 0.22)
            .rotation3DEffect(.degrees(pose.yaw), axis: (x: 0, y: 1, z: 0), perspective: 0.22)
            .offset(pose.offset)
            .frame(width: viewport.width, height: viewport.height)
            .contentShape(Rectangle())
            .coordinateSpace(name: "sceneDragViewport")
            .highPriorityGesture(
                DragGesture(minimumDistance: 10, coordinateSpace: .named("sceneDragViewport"))
                    .updating($translation) { value, state, transaction in
                        guard !reduceMotion else { return }
                        // 短响应弹簧允许回弹途中重新抓取，避免从逻辑零点突然跳变。
                        transaction.animation = .interactiveSpring(response: 0.12, dampingFraction: 1, blendDuration: 0)
                        state = value.translation
                    }
            )
    }
}

public extension View {
    /// 仅用于没有滚动内容的场景入口页；外层继续裁切，并保留同源图片作为衬底。
    func dsSceneDragMotion(viewport: CGSize) -> some View {
        modifier(DSSceneDragMotion(viewport: viewport))
    }
}

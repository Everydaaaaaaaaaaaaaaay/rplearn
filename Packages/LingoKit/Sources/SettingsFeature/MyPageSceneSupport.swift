import Combine
import DesignSystem
import SwiftUI

/// 视觉稿以 iPhone 17 Pro 的 402 pt 宽度为参考；高度严格保持 825 × 1906 母版比例。
/// 任何机型适配都只能缩放这个画布，不能分别重算图片与入口的位置。
enum TravelDeskLayout {
    static let canvasWidth: CGFloat = 402
    static let canvasHeight: CGFloat = canvasWidth * 1906 / 825

    /// 参考画布中最低入口（登录）的视觉与点击范围底边，含少量微光余量。
    /// 短屏按此高度整体缩放，保证入口停在系统 Tab 栏上方。
    static let interactiveContentBottom: CGFloat = 780
}

struct TravelDeskHotspotLayout {
    let center: UnitPoint
    let size: CGSize
    let plane: SceneHologramPlane
    let contentScale: CGFloat
}

struct TravelDeskSceneLayout {
    let assetName: String
    let profile: TravelDeskHotspotLayout
    let coin: TravelDeskHotspotLayout
    let learning: TravelDeskHotspotLayout
    let favorites: TravelDeskHotspotLayout
    let settings: TravelDeskHotspotLayout
    let account: TravelDeskHotspotLayout
    let memory: TravelDeskHotspotLayout

    /// 所有坐标均从 825 × 1906 最终母版逐物件测量，入口与实物轴线成套锁定。
    static let production = TravelDeskSceneLayout(
        assetName: "profile_travel_desk_final",
        profile: .init(
            // 以整个展开的护照夹为定位基准，而非只对齐右侧内页。
            center: UnitPoint(x: 0.205, y: 0.178),
            size: CGSize(width: 104, height: 142),
            plane: .surface(rotationZ: -9, horizontalShadow: 3),
            contentScale: 0.95
        ),
        coin: .init(
            center: UnitPoint(x: 0.84, y: 0.20),
            size: CGSize(width: 112, height: 112),
            plane: .surface(rotationZ: 13.5, horizontalShadow: -3),
            contentScale: 0.88
        ),
        learning: .init(
            center: UnitPoint(x: 0.50, y: 0.495),
            size: CGSize(width: 154, height: 192),
            plane: .surface(rotationZ: -1.5, horizontalShadow: -1),
            contentScale: 1.06
        ),
        favorites: .init(
            center: UnitPoint(x: 0.20, y: 0.72),
            size: CGSize(width: 120, height: 126),
            plane: .surface(rotationZ: -11.5, horizontalShadow: 3),
            contentScale: 1.02
        ),
        settings: .init(
            center: UnitPoint(x: 0.77, y: 0.72),
            size: CGSize(width: 120, height: 128),
            plane: .surface(rotationZ: 12, horizontalShadow: -2),
            contentScale: 0.96
        ),
        account: .init(
            center: UnitPoint(x: 0.505, y: 0.785),
            size: CGSize(width: 126, height: 136),
            plane: .surface(rotationZ: 0, horizontalShadow: -1),
            contentScale: 1.08
        ),
        memory: .init(
            center: UnitPoint(x: 0.54, y: 0.135),
            size: CGSize(width: 116, height: 122),
            plane: .surface(rotationZ: 0, horizontalShadow: 0),
            contentScale: 0.96
        )
    )
}

/// 摄影背景的像素管线与原实现完全一致；`Equatable` 仅阻止入口状态变化时重复求值。
struct MyPageTravelDeskBackground: View, Equatable {
    let assetName: String
    let size: CGSize
    let overlayOpacity: Double

    var body: some View {
        ZStack {
            Image(assetName, bundle: .main)
                .resizable()
                .frame(width: size.width, height: size.height)

            Color.black.opacity(overlayOpacity)
        }
        .frame(width: size.width, height: size.height)
    }
}

/// 短屏衬底保留同一张原图、缩放、模糊和遮罩参数，不用降采样换性能。
struct MyPageCompactTravelDeskBackdrop: View, Equatable {
    let assetName: String
    let size: CGSize
    let overlayOpacity: Double

    var body: some View {
        Image(assetName, bundle: .main)
            .resizable()
            .scaledToFill()
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipped()
            .blur(radius: 5)
            .overlay(Color.black.opacity(overlayOpacity))
    }
}

/// 每个入口都使用承载物自身的局部平面，而不是套用同一组“伪透视”。
/// 参数按 825 × 1906 的母版逐物件校准；足迹方向同时表达悬浮高度与环境光方向。
struct SceneHologramPlane {
    let rotationZ: Double
    let tiltX: Double
    let tiltY: Double
    let perspective: CGFloat
    let scaleX: CGFloat
    let scaleY: CGFloat
    let footprintOffset: CGSize
    let extrusionOffset: CGSize

    static func surface(
        rotationZ: Double,
        horizontalShadow: CGFloat
    ) -> SceneHologramPlane {
        SceneHologramPlane(
            rotationZ: rotationZ,
            tiltX: 6.5,
            tiltY: rotationZ == 0 ? 0 : (rotationZ > 0 ? -1.4 : 1.4),
            perspective: 0.19,
            scaleX: 1,
            scaleY: 0.982,
            footprintOffset: CGSize(width: horizontalShadow, height: 13.5),
            extrusionOffset: CGSize(width: horizontalShadow * 0.25, height: 2.7)
        )
    }

    static let identityHolder = SceneHologramPlane(
        rotationZ: -1.5,
        tiltX: 5,
        tiltY: -1,
        perspective: 0.16,
        scaleX: 1,
        scaleY: 0.985,
        footprintOffset: CGSize(width: 3, height: 13),
        extrusionOffset: CGSize(width: 1, height: 2.6)
    )
    static let camera = SceneHologramPlane(
        rotationZ: 5,
        tiltX: 6,
        tiltY: 1,
        perspective: 0.18,
        scaleX: 1,
        scaleY: 0.99,
        footprintOffset: CGSize(width: 1, height: 13),
        extrusionOffset: CGSize(width: 0.5, height: 2.6)
    )
    static let wallet = SceneHologramPlane(
        rotationZ: 8,
        tiltX: 7,
        tiltY: -2,
        perspective: 0.2,
        scaleX: 1,
        scaleY: 0.98,
        footprintOffset: CGSize(width: -3, height: 13),
        extrusionOffset: CGSize(width: -0.8, height: 2.6)
    )
    static let tablet = SceneHologramPlane(
        rotationZ: 5,
        tiltX: 6,
        tiltY: -1,
        perspective: 0.18,
        scaleX: 1,
        scaleY: 0.985,
        footprintOffset: CGSize(width: -1, height: 14),
        extrusionOffset: CGSize(width: -0.4, height: 2.8)
    )
    static let phrasebook = SceneHologramPlane(
        rotationZ: -2,
        tiltX: 7,
        tiltY: 1.5,
        perspective: 0.2,
        scaleX: 1,
        scaleY: 0.98,
        footprintOffset: CGSize(width: 3, height: 13),
        extrusionOffset: CGSize(width: 0.8, height: 2.6)
    )
    static let watch = SceneHologramPlane(
        rotationZ: 16,
        tiltX: 7,
        tiltY: 1,
        perspective: 0.18,
        scaleX: 1,
        scaleY: 0.98,
        footprintOffset: CGSize(width: -1, height: 14),
        extrusionOffset: CGSize(width: -0.4, height: 2.8)
    )
    static let phone = SceneHologramPlane(
        rotationZ: 4,
        tiltX: 6,
        tiltY: 0,
        perspective: 0.18,
        scaleX: 1,
        scaleY: 0.98,
        footprintOffset: CGSize(width: -2, height: 14),
        extrusionOffset: CGSize(width: -0.6, height: 2.8)
    )
}

struct SceneHologram<Content: View>: View {
    let plane: SceneHologramPlane
    let tint: Color
    let content: Content

    init(
        plane: SceneHologramPlane,
        tint: Color = .sceneHologramYellow,
        @ViewBuilder content: () -> Content
    ) {
        self.plane = plane
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        layers
    }

    private var layers: some View {
        DSHologramSurface(
            transform: DSHologramTransform(
                rotationZ: plane.rotationZ,
                tiltX: plane.tiltX,
                tiltY: plane.tiltY,
                perspective: plane.perspective,
                scaleX: plane.scaleX,
                scaleY: plane.scaleY,
                footprintOffset: plane.footprintOffset,
                extrusionOffset: plane.extrusionOffset
            )
        ) {
            content
        }
    }
}

struct SceneHologramText: View {
    let value: String
    let size: CGFloat
    let weight: Font.Weight
    let tint: Color

    init(
        _ value: String,
        size: CGFloat,
        weight: Font.Weight,
        tint: Color = .sceneHologramYellow
    ) {
        self.value = value
        self.size = size
        self.weight = weight
        self.tint = tint
    }

    var body: some View {
        DSHologramText(
            value,
            size: size,
            weight: weight,
            tint: tint,
            glowColor: .sceneHologramGlowYellow
        )
    }
}

enum SceneHologramGlyph {
    case system(String)
    case coinStacks
    case journeyBook
    case bookmarkStar
    case account
}

struct SceneHologramIcon: View {
    let glyph: SceneHologramGlyph
    let size: CGFloat
    let tint: Color

    init(
        glyph: SceneHologramGlyph,
        size: CGFloat,
        tint: Color = .sceneHologramYellow
    ) {
        self.glyph = glyph
        self.size = size
        self.tint = tint
    }

    @ViewBuilder
    var body: some View {
        switch glyph {
        case .bookmarkStar:
            DSHologramBookmarkIcon(
                size: size,
                tint: tint,
                glowColor: .sceneHologramGlowYellow
            )
        default:
            decoratedGlyph
        }
    }

    private var decoratedGlyph: some View {
        let metrics = DSHologramMaterial.sceneIcon

        return glyphBody
            .frame(width: size, height: size)
            .foregroundStyle(tint.opacity(DSHologramMaterial.coreOpacity))
            .shadow(
                color: Color.sceneHologramGlowYellow.opacity(metrics.outerGlowOpacity),
                radius: metrics.outerGlowRadius
            )
            .shadow(
                color: Color.sceneHologramGlowYellow.opacity(metrics.innerGlowOpacity),
                radius: metrics.innerGlowRadius
            )
            .shadow(
                color: .white.opacity(metrics.edgeLightOpacity),
                radius: metrics.edgeLightRadius,
                x: metrics.edgeLightOffset.width,
                y: metrics.edgeLightOffset.height
            )
            .shadow(
                color: .black.opacity(metrics.depthEdgeOpacity),
                radius: metrics.depthEdgeRadius,
                x: metrics.depthEdgeOffset.width,
                y: metrics.depthEdgeOffset.height
            )
    }

    @ViewBuilder
    private var glyphBody: some View {
        switch glyph {
        case .system(let name):
            Image(systemName: name)
                .font(.system(size: size, weight: .medium))
                .symbolRenderingMode(.monochrome)
        case .coinStacks:
            CoinStacksGlyph()
                .stroke(
                    tint.opacity(DSHologramMaterial.coreOpacity),
                    style: glyphStrokeStyle
                )
                .padding(size * 0.04)
        case .journeyBook:
            JourneyBookGlyph()
                .stroke(
                    tint.opacity(DSHologramMaterial.coreOpacity),
                    style: glyphStrokeStyle
                )
                .padding(size * 0.035)
        case .bookmarkStar:
            ZStack {
                BookmarkGlyph()
                    .stroke(
                        tint.opacity(DSHologramMaterial.coreOpacity),
                        style: glyphStrokeStyle
                    )
                StarGlyph()
                    .fill(tint.opacity(DSHologramMaterial.coreOpacity))
                    .frame(width: size * 0.34, height: size * 0.34)
                    .offset(y: -size * 0.15)
            }
            .padding(size * 0.04)
        case .account:
            ZStack {
                AccountCloudGlyph()
                    .stroke(
                        tint.opacity(DSHologramMaterial.coreOpacity),
                        style: glyphStrokeStyle
                    )
                AccountPersonGlyph()
                    .fill(tint.opacity(DSHologramMaterial.coreOpacity))
            }
            .padding(size * 0.035)
        }
    }

    private var glyphStrokeStyle: StrokeStyle {
        StrokeStyle(
            lineWidth: max(1.7, size * 0.052),
            lineCap: .round,
            lineJoin: .round
        )
    }
}

/// 参考稿中的三组硬币：用统一线宽绘制真实叠放关系，替代含义不明确的双圆点符号。
struct CoinStacksGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        appendStack(
            to: &path,
            in: rect,
            centerX: 0.2,
            top: 0.43,
            bottom: 0.83,
            width: 0.32,
            tiers: 3
        )
        appendStack(
            to: &path,
            in: rect,
            centerX: 0.8,
            top: 0.38,
            bottom: 0.83,
            width: 0.32,
            tiers: 3
        )
        appendStack(
            to: &path,
            in: rect,
            centerX: 0.5,
            top: 0.14,
            bottom: 0.83,
            width: 0.36,
            tiers: 5
        )
        return path
    }

    private func appendStack(
        to path: inout Path,
        in rect: CGRect,
        centerX: CGFloat,
        top: CGFloat,
        bottom: CGFloat,
        width: CGFloat,
        tiers: Int
    ) {
        let stackWidth = rect.width * width
        let ellipseHeight = rect.height * 0.12
        let center = rect.minX + rect.width * centerX
        let left = center - stackWidth / 2
        let right = center + stackWidth / 2
        let topY = rect.minY + rect.height * top
        let bottomY = rect.minY + rect.height * bottom

        path.addEllipse(
            in: CGRect(
                x: left,
                y: topY,
                width: stackWidth,
                height: ellipseHeight
            )
        )
        path.move(to: CGPoint(x: left, y: topY + ellipseHeight / 2))
        path.addLine(to: CGPoint(x: left, y: bottomY))
        path.addCurve(
            to: CGPoint(x: right, y: bottomY),
            control1: CGPoint(x: left, y: bottomY + ellipseHeight * 0.58),
            control2: CGPoint(x: right, y: bottomY + ellipseHeight * 0.58)
        )
        path.addLine(to: CGPoint(x: right, y: topY + ellipseHeight / 2))

        for tier in 1 ..< tiers {
            let fraction = CGFloat(tier) / CGFloat(tiers)
            let y = topY + ellipseHeight / 2 + (bottomY - topY) * fraction
            path.move(to: CGPoint(x: left, y: y))
            path.addCurve(
                to: CGPoint(x: right, y: y),
                control1: CGPoint(x: left, y: y + ellipseHeight * 0.5),
                control2: CGPoint(x: right, y: y + ellipseHeight * 0.5)
            )
        }
    }
}

/// 展开的旅行手册与右页上升路线，保持参考稿的开放、成长语义。
struct JourneyBookGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let point: (CGFloat, CGFloat) -> CGPoint = { x, y in
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        var path = Path()

        path.move(to: point(0.5, 0.84))
        path.addCurve(
            to: point(0.08, 0.7),
            control1: point(0.36, 0.72),
            control2: point(0.2, 0.68)
        )
        path.addLine(to: point(0.08, 0.18))
        path.addCurve(
            to: point(0.5, 0.31),
            control1: point(0.23, 0.14),
            control2: point(0.39, 0.19)
        )
        path.addLine(to: point(0.5, 0.84))
        path.addCurve(
            to: point(0.92, 0.7),
            control1: point(0.64, 0.72),
            control2: point(0.8, 0.68)
        )
        path.addLine(to: point(0.92, 0.18))
        path.addCurve(
            to: point(0.5, 0.31),
            control1: point(0.77, 0.14),
            control2: point(0.61, 0.19)
        )

        path.move(to: point(0.59, 0.59))
        path.addLine(to: point(0.69, 0.48))
        path.addLine(to: point(0.76, 0.54))
        path.addLine(to: point(0.87, 0.39))
        path.move(to: point(0.78, 0.39))
        path.addLine(to: point(0.87, 0.39))
        path.addLine(to: point(0.87, 0.48))
        return path
    }
}

struct BookmarkGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY + rect.height * 0.04))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.88, y: rect.minY + rect.height * 0.04),
            control: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.005)
        )
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.88, y: rect.minY + rect.height * 0.94))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.7))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY + rect.height * 0.94))
        path.closeSubpath()
        return path
    }
}

struct StarGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * 0.46
        var path = Path()
        for index in 0 ..< 10 {
            let radius = index.isMultiple(of: 2) ? outerRadius : innerRadius
            let angle = -CGFloat.pi / 2 + CGFloat(index) * CGFloat.pi / 5
            let point = CGPoint(
                x: center.x + CGFloat(cos(Double(angle))) * radius,
                y: center.y + CGFloat(sin(Double(angle))) * radius
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

/// 参考稿中的账户入口：开放底边的云形轮廓承托人物剪影。
struct AccountCloudGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let point: (CGFloat, CGFloat) -> CGPoint = { x, y in
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        var path = Path()

        path.move(to: point(0.32, 0.42))
        path.addCurve(
            to: point(0.68, 0.42),
            control1: point(0.33, 0.14),
            control2: point(0.67, 0.14)
        )
        path.addCurve(
            to: point(0.73, 0.84),
            control1: point(0.91, 0.38),
            control2: point(1, 0.72)
        )
        path.move(to: point(0.27, 0.84))
        path.addCurve(
            to: point(0.32, 0.42),
            control1: point(0, 0.78),
            control2: point(0.09, 0.38)
        )
        return path
    }
}

struct AccountPersonGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        path.addEllipse(
            in: CGRect(
                x: rect.minX + rect.width * 0.39,
                y: rect.minY + rect.height * 0.38,
                width: rect.width * 0.22,
                height: rect.height * 0.22
            )
        )
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.minY + rect.height * 0.84))
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.72, y: rect.minY + rect.height * 0.84),
            control1: CGPoint(x: rect.minX + rect.width * 0.3, y: rect.minY + rect.height * 0.61),
            control2: CGPoint(x: rect.minX + rect.width * 0.7, y: rect.minY + rect.height * 0.61)
        )
        path.closeSubpath()
        return path
    }
}

/// “我的”页场景入口使用更明确的按下反馈。
///
/// 入口本身悬浮在摄影物件上，按下时应像被手指压回承载面：缩小、下沉并稍微收敛亮度；
/// 松手后由短促弹簧回到原位。静止状态不改变现有图标、文字或透视。
struct MyPageSceneEntranceButtonStyle: ButtonStyle {
    let keepsPressedAppearance: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let isVisuallyPressed = configuration.isPressed || keepsPressedAppearance

        configuration.label
            .scaleEffect(reduceMotion || !isVisuallyPressed ? 1 : DSSceneEntranceMotion.pressedScale)
            .offset(y: reduceMotion || !isVisuallyPressed ? 0 : DSSceneEntranceMotion.pressedOffset)
            .brightness(isVisuallyPressed ? DSSceneEntranceMotion.pressedBrightness : 0)
            .opacity(isVisuallyPressed ? DSSceneEntranceMotion.pressedOpacity : 1)
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.08)
                    : isVisuallyPressed
                        ? .spring(
                            response: DSSceneEntranceMotion.pressResponse,
                            dampingFraction: DSSceneEntranceMotion.pressDampingFraction
                        )
                        : .spring(
                            duration: DSSceneEntranceMotion.releaseDuration,
                            bounce: DSSceneEntranceMotion.releaseBounce
                        ),
                value: isVisuallyPressed
            )
    }
}

enum MyPageSceneHotspot: Hashable {
    case profile
    case coin
    case learning
    case favorites
    case settings
    case account
    case memory
}

/// 护照夹上的身份投影作为一个整体旋转和定位，避免头像与文字分别漂移。
struct MyPageProfileSceneEntry: View {
    let plane: SceneHologramPlane
    let scale: CGFloat
    let displayName: String
    let accountBadgeTitle: String
    let occupiedFriendSlots: Int

    var body: some View {
        SceneHologram(plane: plane) {
            VStack(spacing: 4 * scale) {
                SceneHologramIcon(
                    glyph: .system("person.crop.circle"),
                    size: 44 * scale,
                    tint: .sceneHologramYellow
                )

                VStack(spacing: 1.5 * scale) {
                    SceneHologramText(displayName, size: 17 * scale, weight: .bold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    SceneHologramText(accountBadgeTitle, size: 14 * scale, weight: .semibold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                    SceneHologramText("\(occupiedFriendSlots) 位旅途朋友", size: 13 * scale, weight: .medium)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                }
                .frame(width: 94 * scale)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == MyPageSceneEntranceButtonStyle {
    static func myPageSceneEntrance(
        keepsPressedAppearance: Bool = false
    ) -> MyPageSceneEntranceButtonStyle {
        MyPageSceneEntranceButtonStyle(keepsPressedAppearance: keepsPressedAppearance)
    }
}

extension Color {
    /// “我的”页与首页共享同一暖象牙白核心，避免入口之间出现色温漂移。
    static let sceneHologramYellow = DSHologramPalette.ivory

    /// 更暖的淡金衰减层只存在于核心外侧，主体仍然保持接近白色。
    static let sceneHologramGlowYellow = DSHologramPalette.glow
}

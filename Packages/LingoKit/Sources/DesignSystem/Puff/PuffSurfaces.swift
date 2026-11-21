import SwiftUI

// MARK: - 厚卡片

/// 白色正面 + 细描边 + 底部唇边。看起来像一块可以按下去的软糖。
private struct PuffChunkyBackground: ViewModifier {
    let radius: CGFloat
    let face: Color
    let border: Color
    let lip: Color
    let lipHeight: CGFloat
    let pressed: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background { shape.fill(face) }
            .overlay { shape.strokeBorder(border, lineWidth: 1.5) }
            .offset(y: pressed ? lipHeight * 0.8 : 0)
            .padding(.bottom, lipHeight)
            .background {
                shape
                    .fill(lip)
                    .padding(.top, lipHeight)
            }
            .contentShape(.contextMenuPreview, shape)
            .contentShape(shape)
    }
}

public extension View {
    /// 静态厚卡片。
    func puffCard(
        radius: CGFloat = Puff.Radius.large,
        face: Color = Puff.Palette.card,
        border: Color = Puff.Palette.line,
        lip: Color = Puff.Palette.lip,
        lipHeight: CGFloat = Puff.Lip.card
    ) -> some View {
        modifier(PuffChunkyBackground(radius: radius, face: face, border: border, lip: lip, lipHeight: lipHeight, pressed: false))
    }
}

/// 整张卡片都是按钮：按下时正面陷进唇边，松手时轻轻弹回。
public struct PuffCardButtonStyle: ButtonStyle {
    private let radius: CGFloat
    private let face: Color
    private let border: Color
    private let lip: Color
    private let lipHeight: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        radius: CGFloat = Puff.Radius.large,
        face: Color = Puff.Palette.card,
        border: Color = Puff.Palette.line,
        lip: Color = Puff.Palette.lip,
        lipHeight: CGFloat = Puff.Lip.card
    ) {
        self.radius = radius
        self.face = face
        self.border = border
        self.lip = lip
        self.lipHeight = lipHeight
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(PuffChunkyBackground(
                radius: radius, face: face, border: border, lip: lip,
                lipHeight: lipHeight, pressed: configuration.isPressed
            ))
            .animation(
                reduceMotion ? nil : (configuration.isPressed ? Puff.Motion.press : Puff.Motion.release),
                value: configuration.isPressed
            )
    }
}

/// 实心糖果按钮：白字、彩色正面、深色唇边。
public struct PuffCandyButtonStyle: ButtonStyle {
    private let candy: PuffCandy
    private let radius: CGFloat
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(_ candy: PuffCandy = .sky, radius: CGFloat = Puff.Radius.medium) {
        self.candy = candy
        self.radius = radius
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.puff(.headline, .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, Puff.Space.l)
            .frame(minHeight: 48)
            .modifier(PuffChunkyBackground(
                radius: radius, face: candy.base, border: .clear, lip: candy.lip,
                lipHeight: Puff.Lip.button, pressed: configuration.isPressed
            ))
            .opacity(isEnabled ? 1 : 0.5)
            .animation(
                reduceMotion ? nil : (configuration.isPressed ? Puff.Motion.press : Puff.Motion.release),
                value: configuration.isPressed
            )
    }
}

/// 图标、小胶囊等小按钮：按下时软软地缩一下，松手回弹。
public struct PuffSquishButtonStyle: ButtonStyle {
    private let scale: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(scale: CGFloat = 0.88) {
        self.scale = scale
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.7 : 1)
            .animation(configuration.isPressed ? Puff.Motion.press : Puff.Motion.release, value: configuration.isPressed)
    }
}

/// 分组卡片内的行：按下时出现一块圆角浅底并轻微缩小。
public struct PuffRowButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: Puff.Radius.medium, style: .continuous)
                    .fill(Puff.Palette.cloud)
                    .padding(.horizontal, 6)
                    .opacity(configuration.isPressed ? 1 : 0)
            }
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(configuration.isPressed ? Puff.Motion.press : Puff.Motion.release, value: configuration.isPressed)
    }
}

public extension ButtonStyle where Self == PuffSquishButtonStyle {
    static var puffSquish: PuffSquishButtonStyle { PuffSquishButtonStyle() }
}

public extension ButtonStyle where Self == PuffRowButtonStyle {
    static var puffRow: PuffRowButtonStyle { PuffRowButtonStyle() }
}

public extension ButtonStyle where Self == PuffCardButtonStyle {
    static var puffCard: PuffCardButtonStyle { PuffCardButtonStyle() }
}

// MARK: - 进场与弹出

private struct PuffEntranceModifier: ViewModifier {
    let index: Int
    let isShown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isShown ? 1 : 0)
            .offset(y: isShown || reduceMotion ? 0 : 22)
            .scaleEffect(isShown || reduceMotion ? 1 : 0.96, anchor: .top)
            .animation(Puff.Motion.resolve(Puff.Motion.entrance(index), reduceMotion: reduceMotion), value: isShown)
    }
}

public extension View {
    /// 首屏内容逐行错峰弹入。`isShown` 由页面在首次拿到数据后置为 true，之后不再回退，
    /// 因此滚动时新出现的行不会重复播放。
    func puffEntrance(index: Int, isShown: Bool) -> some View {
        modifier(PuffEntranceModifier(index: index, isShown: isShown))
    }
}

public extension AnyTransition {
    /// 小元素从中心弹出、缩回消失。
    static var puffPop: AnyTransition {
        .scale(scale: 0.3).combined(with: .opacity)
    }

    /// 内容从上方轻落下来。
    static var puffDrop: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: -10)).combined(with: .scale(scale: 0.97, anchor: .top)),
            removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
        )
    }
}

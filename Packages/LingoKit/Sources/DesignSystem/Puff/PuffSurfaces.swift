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

// MARK: - 轻点反馈

/// 滚动区域里的快速轻点，系统要等手指抬起才显示按下效果，动作又在同一刻触发，页面一切走反馈就看不见了。
/// 轻点后让按下的样子停留 `Puff.Motion.tapHold` 再触发动作，下压与回弹因此看得见。
///
/// 看得见、读得到的是原按钮本身（`Button(configuration)`）：标签、值、提示、标识都原样保留，
/// VoiceOver 激活立即执行。触摸交给盖在上面的透明原生按钮（对辅助功能隐藏），
/// 滚动取消等手势仍是系统行为。同一时刻只允许一个按钮处在停留中，快速连点两个入口不会连续推入两页。
@MainActor
private enum PuffTapGate {
    static var isHolding = false
}

/// 只读出原生按钮的按下状态，供原按钮画出按下的样子。
private struct PuffPressReader: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, pressed in isPressed = pressed }
    }
}

/// 盖在原按钮上的透明触摸层。
private struct PuffTouchLayer: View {
    @Binding var isPressed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Color.clear.contentShape(Rectangle())
        }
        .buttonStyle(PuffPressReader(isPressed: $isPressed))
        .accessibilityHidden(true)
    }
}

private struct PuffHeldButton<Face: ButtonStyle>: View {
    let configuration: PrimitiveButtonStyleConfiguration
    let face: (_ isHeld: Bool) -> Face
    @State private var isHeld = false
    @State private var isTouching = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    var body: some View {
        Button(configuration)
            .buttonStyle(face(isHeld || isTouching))
            .allowsHitTesting(false)
            .overlay {
                PuffTouchLayer(isPressed: $isTouching) {
                    guard !isHeld, !PuffTapGate.isHolding else { return }
                    guard !reduceMotion, !voiceOver else {
                        configuration.trigger()
                        return
                    }
                    isHeld = true
                    PuffTapGate.isHolding = true
                    Task { @MainActor in
                        try? await Task.sleep(for: Puff.Motion.tapHold)
                        isHeld = false
                        PuffTapGate.isHolding = false
                        configuration.trigger()
                    }
                }
            }
    }
}

/// 整张卡片都是按钮：按下时正面陷进唇边、整体缩一点并给一下软触感，松手时弹回。
public struct PuffCardButtonStyle: PrimitiveButtonStyle {
    private let radius: CGFloat
    private let face: Color
    private let border: Color
    private let lip: Color
    private let lipHeight: CGFloat

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
        PuffHeldButton(configuration: configuration) { isHeld in
            PuffCardFace(radius: radius, face: face, border: border, lip: lip, lipHeight: lipHeight, isHeld: isHeld)
        }
    }
}

private struct PuffCardFace: ButtonStyle {
    let radius: CGFloat
    let face: Color
    let border: Color
    let lip: Color
    let lipHeight: CGFloat
    let isHeld: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed || isHeld
        return configuration.label
            .modifier(PuffChunkyBackground(
                radius: radius, face: face, border: border, lip: lip,
                lipHeight: lipHeight, pressed: pressed
            ))
            .scaleEffect(pressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : (pressed ? Puff.Motion.press : Puff.Motion.release), value: pressed)
            .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.5), trigger: pressed) { _, now in now }
    }
}

/// 实心糖果按钮：白字、彩色正面、深色唇边。按下时压扁陷进唇边，松手像果冻一样晃回来。
public struct PuffCandyButtonStyle: PrimitiveButtonStyle {
    private let candy: PuffCandy
    private let radius: CGFloat

    public init(_ candy: PuffCandy = .sky, radius: CGFloat = Puff.Radius.medium) {
        self.candy = candy
        self.radius = radius
    }

    public func makeBody(configuration: Configuration) -> some View {
        PuffHeldButton(configuration: configuration) { isHeld in
            PuffCandyFace(candy: candy, radius: radius, isHeld: isHeld)
        }
    }
}

private struct PuffCandyFace: ButtonStyle {
    let candy: PuffCandy
    let radius: CGFloat
    let isHeld: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed || isHeld
        let squashed = pressed && !reduceMotion
        return configuration.label
            .font(.puff(.headline, Puff.Weight.title))
            .foregroundStyle(.white)
            .padding(.horizontal, Puff.Space.l)
            .frame(minHeight: 48)
            .modifier(PuffChunkyBackground(
                radius: radius, face: candy.base, border: .clear, lip: candy.lip,
                lipHeight: Puff.Lip.button, pressed: pressed
            ))
            .scaleEffect(x: squashed ? 1.04 : 1, y: squashed ? 0.93 : 1, anchor: .bottom)
            .opacity(isEnabled ? 1 : 0.5)
            .animation(reduceMotion ? nil : (pressed ? Puff.Motion.press : Puff.Motion.jelly), value: pressed)
            .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: pressed) { _, now in now }
    }
}

/// 图标、小胶囊等小按钮：按下时软软地缩一下，松手回弹，里面的图标顺势蹦一下。
/// 动作立即执行，不等反馈；轻点时按下的样子同样停留 `Puff.Motion.tapHold`。
public struct PuffSquishButtonStyle: PrimitiveButtonStyle {
    private let scale: CGFloat
    private let haptic: Bool

    /// - Parameter haptic: 按钮动作自己会给触感（如筛选切换）时传 false，避免叠两次。
    public init(scale: CGFloat = 0.88, haptic: Bool = true) {
        self.scale = scale
        self.haptic = haptic
    }

    public func makeBody(configuration: Configuration) -> some View {
        PuffSquishButton(configuration: configuration, scale: scale, haptic: haptic)
    }
}

private struct PuffSquishButton: View {
    let configuration: PrimitiveButtonStyleConfiguration
    let scale: CGFloat
    let haptic: Bool
    @State private var taps = 0
    @State private var isTouching = false

    var body: some View {
        Button(configuration)
            .buttonStyle(PuffSquishFace(scale: scale, haptic: haptic, taps: taps, isTouching: isTouching))
            .allowsHitTesting(false)
            .overlay {
                PuffTouchLayer(isPressed: $isTouching) {
                    configuration.trigger()
                    taps += 1
                }
            }
    }
}

private struct PuffSquishFace: ButtonStyle {
    let scale: CGFloat
    let haptic: Bool
    let taps: Int
    let isTouching: Bool

    func makeBody(configuration: Configuration) -> some View {
        PuffSquishBody(configuration: configuration, scale: scale, haptic: haptic, taps: taps, isTouching: isTouching)
    }
}

private struct PuffSquishBody: View {
    let configuration: ButtonStyleConfiguration
    let scale: CGFloat
    let haptic: Bool
    let taps: Int
    let isTouching: Bool
    @State private var isHeld = false
    @State private var releases = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let pressed = configuration.isPressed || isTouching || isHeld
        configuration.label
            .symbolEffect(.bounce.up, options: .nonRepeating, value: releases)
            .scaleEffect(pressed && !reduceMotion ? scale : 1)
            .opacity(pressed && reduceMotion ? 0.7 : 1)
            .animation(pressed ? Puff.Motion.press : Puff.Motion.release, value: pressed)
            .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.4), trigger: pressed) { _, now in
                haptic && now
            }
            .task(id: taps) {
                guard taps > 0 else { return }
                isHeld = true
                do { try await Task.sleep(for: Puff.Motion.tapHold) } catch { return }
                isHeld = false
                if !reduceMotion { releases += 1 }
            }
    }
}

/// 分组卡片内的行：按下时出现一块圆角浅底并轻微缩小，停留片刻再进入下一页，像原生列表的选中高亮。
public struct PuffRowButtonStyle: PrimitiveButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        PuffHeldButton(configuration: configuration) { isHeld in
            PuffRowFace(isHeld: isHeld)
        }
    }
}

private struct PuffRowFace: ButtonStyle {
    let isHeld: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed || isHeld
        return configuration.label
            .background {
                RoundedRectangle(cornerRadius: Puff.Radius.medium, style: .continuous)
                    .fill(Puff.Palette.cloud)
                    .padding(.horizontal, 6)
                    .opacity(pressed ? 1 : 0)
            }
            .scaleEffect(pressed && !reduceMotion ? 0.98 : 1)
            .animation(pressed ? Puff.Motion.press : Puff.Motion.release, value: pressed)
    }
}

public extension PrimitiveButtonStyle where Self == PuffSquishButtonStyle {
    static var puffSquish: PuffSquishButtonStyle { PuffSquishButtonStyle() }
}

public extension PrimitiveButtonStyle where Self == PuffRowButtonStyle {
    static var puffRow: PuffRowButtonStyle { PuffRowButtonStyle() }
}

public extension PrimitiveButtonStyle where Self == PuffCardButtonStyle {
    static var puffCard: PuffCardButtonStyle { PuffCardButtonStyle() }
}

// MARK: - 推入页面的内容进场

/// 推入页面的主栈，用法同 `VStack`。系统推入、导航栏和左缘返回保持原样，
/// 页面里的各块内容在推入的同时自下而上错峰浮现；只在页面首次出现时播放，返回到这一页不重播。
public struct PuffStaggeredStack<Content: View>: View {
    private let alignment: HorizontalAlignment
    private let spacing: CGFloat?
    private let content: Content
    @State private var isShown = false

    public init(
        alignment: HorizontalAlignment = .center,
        spacing: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: alignment, spacing: spacing) {
            Group(subviews: content) { subviews in
                ForEach(Array(subviews.enumerated()), id: \.element.id) { index, subview in
                    subview.puffEntrance(index: index, isShown: isShown)
                }
            }
        }
        .onAppear { isShown = true }
    }
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

// MARK: - 新内容弹出

private struct PuffArrivalModifier: ViewModifier {
    let anchor: UnitPoint
    let onArrive: () -> Void
    @State private var isShown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(isNew: Bool, anchor: UnitPoint, onArrive: @escaping () -> Void) {
        self.anchor = anchor
        self.onArrive = onArrive
        _isShown = State(initialValue: !isNew)
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(isShown || reduceMotion ? 1 : 0.5, anchor: anchor)
            .offset(y: isShown || reduceMotion ? 0 : 12)
            .opacity(isShown ? 1 : 0)
            .onAppear {
                guard !isShown else { return }
                onArrive()
                withAnimation(Puff.Motion.resolve(Puff.Motion.arrival, reduceMotion: reduceMotion)) {
                    isShown = true
                }
            }
    }
}

public extension View {
    /// 刚产生的内容（新消息、新卡片）从 `anchor` 处弹出来；历史内容原样显示。
    /// 只改变绘制，不改变布局，因此不会扰动滚动位置。`onArrive` 在弹出开始时调用一次，
    /// 供列表记住“已经播过”，避免懒加载行重新出现时重复播放。
    func puffArrival(isNew: Bool, anchor: UnitPoint = .bottom, onArrive: @escaping () -> Void = {}) -> some View {
        modifier(PuffArrivalModifier(isNew: isNew, anchor: anchor, onArrive: onArrive))
    }
}

// MARK: - 缩放转场

public extension EnvironmentValues {
    /// 导航栈提供的缩放转场命名空间。页面用 `puffZoomSource` 标记起点，导航目标用同一个 id 缩放展开。
    @Entry var puffZoomNamespace: Namespace.ID? = nil
}

private struct PuffZoomSourceModifier<ID: Hashable>: ViewModifier {
    let id: ID
    let namespace: Namespace.ID?
    let cornerRadius: CGFloat
    @Environment(\.puffZoomNamespace) private var environmentNamespace

    func body(content: Content) -> some View {
        if let namespace = namespace ?? environmentNamespace {
            content.matchedTransitionSource(id: id, in: namespace) { source in
                source.clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        } else {
            content
        }
    }
}

public extension View {
    /// 标记缩放转场的起点。未提供命名空间时读取导航栈注入的 `puffZoomNamespace`，都没有时不做任何事。
    func puffZoomSource(id: some Hashable, in namespace: Namespace.ID? = nil, cornerRadius: CGFloat = Puff.Radius.large) -> some View {
        modifier(PuffZoomSourceModifier(id: id, namespace: namespace, cornerRadius: cornerRadius))
    }
}

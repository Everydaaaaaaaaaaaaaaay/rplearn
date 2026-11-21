import SwiftUI

// MARK: - 头像

/// 在线状态小圆点。
public enum PuffPresence: Sendable, Equatable {
    case online
    case recentlyActive
    case offline

    var color: Color {
        switch self {
        case .online: PuffCandy.mint.base
        case .recentlyActive: PuffCandy.sunny.base
        case .offline: Puff.Palette.inkFaint
        }
    }
}

/// 糖果色外圈 + 白色间隙 + 头像。颜色由名字稳定决定。
public struct PuffAvatar: View {
    private let name: String
    private let size: CGFloat
    private let imageName: String?
    private let remoteURL: URL?
    private let candy: PuffCandy
    private let presence: PuffPresence?

    public init(
        name: String,
        size: CGFloat = 56,
        imageName: String? = nil,
        remoteURL: URL? = nil,
        candy: PuffCandy? = nil,
        presence: PuffPresence? = nil
    ) {
        self.name = name
        self.size = size
        self.imageName = imageName
        self.remoteURL = remoteURL
        self.candy = candy ?? PuffCandy.stable(for: name)
        self.presence = presence
    }

    public var body: some View {
        let ring = max(2.5, size * 0.05)
        ZStack {
            Circle().fill(candy.base)
            Circle().fill(Puff.Palette.card).padding(ring)
            AvatarBadge(
                name: name,
                tint: candy.base,
                size: size - ring * 4,
                imageName: imageName,
                remoteURL: remoteURL,
                usesPendingPlaceholder: true
            )
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            if let presence {
                Circle()
                    .fill(presence.color)
                    .frame(width: size * 0.24, height: size * 0.24)
                    .overlay { Circle().strokeBorder(Puff.Palette.card, lineWidth: max(2, size * 0.045)) }
                    .offset(x: 1, y: 1)
                    .transition(.puffPop)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - 角标与标签

/// 未读数胶囊，数字变化时滚动切换。
public struct PuffCountBadge: View {
    private let count: Int

    public init(_ count: Int) {
        self.count = count
    }

    public var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.puff(.caption, Puff.Weight.emphasis))
            .monospacedDigit()
            .foregroundStyle(.white)
            .contentTransition(.numericText(value: Double(count)))
            .padding(.horizontal, 7)
            .frame(minWidth: 24, minHeight: 24)
            .background(Puff.Palette.cherry, in: Capsule())
            .overlay { Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1) }
            .accessibilityLabel("\(count) 条未读")
    }
}

/// 浅底彩字的小胶囊标签。
public struct PuffTag: View {
    private let title: String
    private let systemImage: String?
    private let candy: PuffCandy

    public init(_ title: String, systemImage: String? = nil, candy: PuffCandy = .sky) {
        self.title = title
        self.systemImage = systemImage
        self.candy = candy
    }

    public var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: Puff.Weight.icon))
            }
            Text(title)
                .lineLimit(1)
        }
        .font(.puff(.caption2, Puff.Weight.emphasis))
        .foregroundStyle(candy.deep)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(candy.wash, in: Capsule())
        .fixedSize()
    }
}

/// 圆角方块里的图标，用于分组标题。
public struct PuffIconBubble: View {
    private let systemImage: String
    private let candy: PuffCandy
    private let size: CGFloat

    public init(_ systemImage: String, candy: PuffCandy, size: CGFloat = 36) {
        self.systemImage = systemImage
        self.candy = candy
        self.size = size
    }

    public var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.46, weight: Puff.Weight.icon, design: .rounded))
            .foregroundStyle(candy.deep)
            .frame(width: size, height: size)
            .background(candy.wash, in: RoundedRectangle(cornerRadius: size * 0.34, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - 筛选条

/// 横向胶囊筛选。选中的胶囊像果冻一样滑过去。
public struct PuffFilterBar<Value: Hashable>: View {
    public struct Option: Identifiable {
        public let value: Value
        public let title: String
        public let systemImage: String?
        public let count: Int?
        public var id: Value { value }

        public init(_ value: Value, title: String, systemImage: String? = nil, count: Int? = nil) {
            self.value = value
            self.title = title
            self.systemImage = systemImage
            self.count = count
        }
    }

    @Binding private var selection: Value
    private let options: [Option]
    private let candy: PuffCandy
    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(selection: Binding<Value>, options: [Option], candy: PuffCandy = .sky) {
        _selection = selection
        self.options = options
        self.candy = candy
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Puff.Space.xs) {
                ForEach(options) { option in
                    chip(option)
                }
            }
            .padding(.horizontal, Puff.Space.m)
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    private func chip(_ option: Option) -> some View {
        let isSelected = option.value == selection
        return Button {
            guard !isSelected else { return }
            Haptics.selection()
            withAnimation(Puff.Motion.resolve(Puff.Motion.bouncy, reduceMotion: reduceMotion)) {
                selection = option.value
            }
        } label: {
            HStack(spacing: 5) {
                if let systemImage = option.systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: Puff.Weight.icon))
                }
                Text(option.title)
                if let count = option.count, count > 0 {
                    Text("\(count)")
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(count)))
                        .padding(.horizontal, 6)
                        .frame(minHeight: 18)
                        .background(isSelected ? Color.white.opacity(0.28) : candy.wash, in: Capsule())
                }
            }
            .font(.puff(.subheadline, Puff.Weight.emphasis))
            .foregroundStyle(isSelected ? .white : Puff.Palette.inkSoft)
            .padding(.horizontal, 14)
            .frame(minHeight: 38)
            .background {
                if isSelected {
                    Capsule()
                        .fill(candy.lip)
                        .offset(y: Puff.Lip.chip)
                        .overlay { Capsule().fill(candy.base) }
                        .matchedGeometryEffect(id: "selection", in: namespace)
                } else {
                    Capsule()
                        .fill(Puff.Palette.cloud)
                }
            }
            .padding(.bottom, Puff.Lip.chip)
        }
        .buttonStyle(.puffSquish)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - 小云朵伙伴

/// 程序化绘制的“小云”：会眨眼、轻轻上下浮动。用于空状态和加载。
public struct PuffCloudBuddy: View {
    public enum Mood: Sendable {
        case happy
        case curious
        case sleepy
    }

    private let mood: Mood
    private let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(_ mood: Mood = .happy, size: CGFloat = 120) {
        self.mood = mood
        self.size = size
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3_600)
            Canvas { context, canvasSize in
                draw(context, canvasSize, time: time)
            }
        }
        .frame(width: size, height: size * 0.82)
        .accessibilityHidden(true)
    }

    private func draw(_ context: GraphicsContext, _ canvasSize: CGSize, time: TimeInterval) {
        let unit = canvasSize.width / 100
        let bob = CGFloat(sin(time * 2.1)) * 2.4 * unit
        let squash = 1 + CGFloat(sin(time * 4.2)) * 0.012
        var context = context
        context.translateBy(x: canvasSize.width / 2, y: canvasSize.height * 0.56 + bob)
        context.scaleBy(x: unit * squash, y: unit / squash)

        // 地面阴影随浮动变大变小。
        let shadowWidth = 52 - bob / unit * 2
        context.fill(
            Path(ellipseIn: CGRect(x: -shadowWidth / 2, y: 30 - bob / unit, width: shadowWidth, height: 6)),
            with: .color(Color(red: 0.62, green: 0.7, blue: 0.88).opacity(0.22))
        )

        // 合并成一个外轮廓，描边时不会露出内部重叠的圆。
        let body = Path(roundedRect: CGRect(x: -40, y: -6, width: 80, height: 32), cornerRadius: 16, style: .continuous)
            .union(Path(ellipseIn: CGRect(x: -36, y: -26, width: 36, height: 36)))
            .union(Path(ellipseIn: CGRect(x: -12, y: -38, width: 42, height: 42)))
            .union(Path(ellipseIn: CGRect(x: 14, y: -20, width: 28, height: 28)))
        context.fill(body.offsetBy(dx: 0, dy: 4), with: .color(Color(red: 0.86, green: 0.9, blue: 0.98)))
        context.fill(body, with: .color(.white))
        context.stroke(body, with: .color(Color(red: 0.84, green: 0.88, blue: 0.97)), lineWidth: 1.4)

        let ink = Color(red: 0.17, green: 0.19, blue: 0.32)
        let blink = time.truncatingRemainder(dividingBy: 3.8) < 0.14
        for side in [-1.0, 1.0] as [CGFloat] {
            let eye = CGPoint(x: side * 12, y: 0)
            switch mood {
            case .sleepy:
                var lid = Path()
                lid.move(to: CGPoint(x: eye.x - 4.5, y: eye.y))
                lid.addQuadCurve(to: CGPoint(x: eye.x + 4.5, y: eye.y), control: CGPoint(x: eye.x, y: eye.y + 4))
                context.stroke(lid, with: .color(ink), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            default:
                let height: CGFloat = blink ? 1.4 : (mood == .curious ? 9 : 8)
                context.fill(Path(ellipseIn: CGRect(x: eye.x - 3.6, y: eye.y - height / 2, width: 7.2, height: height)), with: .color(ink))
                if !blink {
                    context.fill(Path(ellipseIn: CGRect(x: eye.x - 1.6, y: eye.y - height / 2 + 1.2, width: 2.6, height: 2.6)), with: .color(.white))
                }
            }
            context.fill(
                Path(ellipseIn: CGRect(x: eye.x + side * 4 - 5, y: eye.y + 6, width: 10, height: 5)),
                with: .color(Color(red: 1, green: 0.6, blue: 0.7).opacity(0.55))
            )
        }
        var mouth = Path()
        switch mood {
        case .happy:
            mouth.move(to: CGPoint(x: -5, y: 7))
            mouth.addQuadCurve(to: CGPoint(x: 5, y: 7), control: CGPoint(x: 0, y: 13))
            context.stroke(mouth, with: .color(ink), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        case .curious:
            context.fill(Path(ellipseIn: CGRect(x: -2.6, y: 7, width: 5.2, height: 5.6)), with: .color(ink))
        case .sleepy:
            mouth.move(to: CGPoint(x: -3, y: 9))
            mouth.addQuadCurve(to: CGPoint(x: 3, y: 9), control: CGPoint(x: 0, y: 11))
            context.stroke(mouth, with: .color(ink), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            let float = CGFloat((time * 0.8).truncatingRemainder(dividingBy: 1))
            context.draw(
                Text("z").font(.system(size: 9 + float * 5, weight: Puff.Weight.icon, design: .rounded)).foregroundColor(Color(red: 0.55, green: 0.62, blue: 0.85).opacity(1 - Double(float))),
                at: CGPoint(x: 30 + float * 8, y: -30 - float * 14)
            )
        }
    }
}

/// 空状态：小云 + 标题 + 说明 + 可选操作。
public struct PuffEmptyState<Actions: View>: View {
    private let mood: PuffCloudBuddy.Mood
    private let title: String
    private let message: String?
    private let actions: Actions

    public init(
        _ title: String,
        message: String? = nil,
        mood: PuffCloudBuddy.Mood = .happy,
        @ViewBuilder actions: () -> Actions = { EmptyView() }
    ) {
        self.title = title
        self.message = message
        self.mood = mood
        self.actions = actions()
    }

    public var body: some View {
        VStack(spacing: Puff.Space.s) {
            PuffCloudBuddy(mood, size: 120)
            VStack(spacing: 6) {
                Text(title)
                    .font(.puff(.title3, Puff.Weight.title))
                    .foregroundStyle(Puff.Palette.ink)
                if let message {
                    Text(message)
                        .font(.puff(.subheadline, Puff.Weight.body))
                        .foregroundStyle(Puff.Palette.inkSoft)
                }
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
            actions
                .padding(.top, Puff.Space.xs)
        }
        .padding(.horizontal, Puff.Space.xl)
        .padding(.vertical, Puff.Space.l)
        .frame(maxWidth: 360)
    }
}

/// 三颗糖果色圆点依次跳动的加载指示。
public struct PuffLoadingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    let phase = sin(time * 6 - Double(index) * 0.8)
                    Circle()
                        .fill([PuffCandy.sky, .bubblegum, .sunny][index].base)
                        .frame(width: 12, height: 12)
                        .offset(y: reduceMotion ? 0 : CGFloat(min(phase, 0)) * 8)
                        .scaleEffect(x: 1 + CGFloat(max(phase, 0)) * 0.12, y: 1 - CGFloat(max(phase, 0)) * 0.12, anchor: .bottom)
                }
            }
            .frame(height: 24)
        }
        .accessibilityElement()
        .accessibilityLabel("正在加载")
    }
}

// MARK: - 城市明信片

/// 城市文案与时间。场景内部配方不对外暴露，页面只需要城市名和当地时间。
public enum PuffCity {
    public static func nameZh(for regionID: String?) -> String {
        PuffCityCatalog.nameZh(for: regionID)
    }

    public static func timeZone(for regionID: String?) -> TimeZone {
        TimeZone(identifier: PuffCityCatalog.recipe(for: regionID).timeZoneID) ?? .current
    }

    public static func hour(for regionID: String?, at date: Date = .now) -> Int {
        PuffCityCatalog.recipe(for: regionID).clock(at: date).hour ?? 12
    }

    /// “早上好”这类随城市当地时间变化的问候。
    public static func greeting(for regionID: String?, at date: Date = .now) -> String {
        switch hour(for: regionID, at: date) {
        case 5..<11: "早上好"
        case 11..<14: "中午好"
        case 14..<18: "下午好"
        case 18..<22: "晚上好"
        default: "夜深啦"
        }
    }

    /// 城市当地的 “10:09”。
    public static func localTime(for regionID: String?, at date: Date = .now) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = timeZone(for: regionID)
        return date.formatted(style)
    }
}

/// 上半部是卡通城市场景、下半部是白色说明区的厚卡片。
public struct PuffSceneCard<Caption: View>: View {
    private let regionID: String?
    private let viewport: PuffCityScene.Viewport
    private let sceneHeight: CGFloat
    private let isActive: Bool
    private let caption: Caption

    public init(
        regionID: String?,
        viewport: PuffCityScene.Viewport = .west,
        sceneHeight: CGFloat = 150,
        isActive: Bool = true,
        @ViewBuilder caption: () -> Caption
    ) {
        self.regionID = regionID
        self.viewport = viewport
        self.sceneHeight = sceneHeight
        self.isActive = isActive
        self.caption = caption()
    }

    public var body: some View {
        VStack(spacing: 0) {
            PuffCityScene(regionID: regionID, viewport: viewport, isActive: isActive)
                .frame(height: sceneHeight)
                .clipShape(RoundedRectangle(cornerRadius: Puff.Radius.huge - 6, style: .continuous))
                .padding([.horizontal, .top], 6)
            caption
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Puff.Space.m)
                .padding(.top, Puff.Space.s)
                .padding(.bottom, Puff.Space.m)
        }
        .puffCard(radius: Puff.Radius.huge)
    }
}

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

/// 细糖果色外圈 + 细白缝 + 头像。颜色由名字稳定决定。
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
        let ring = max(1.5, size * 0.036)
        let gap = max(1.25, size * 0.03)
        ZStack {
            Circle().fill(candy.base)
            Circle().fill(Puff.Palette.card).padding(ring)
            AvatarBadge(
                name: name,
                tint: candy.base,
                size: size - (ring + gap) * 2,
                imageName: imageName,
                remoteURL: remoteURL,
                usesPendingPlaceholder: true,
                isFramed: false
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

/// 未读数胶囊，数字变化时滚动切换，数字变多时蹦一下。
public struct PuffCountBadge: View {
    private let count: Int
    @State private var bumps = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            .keyframeAnimator(initialValue: CGFloat(1), trigger: bumps) { badge, scale in
                badge.scaleEffect(scale)
            } keyframes: { _ in
                SpringKeyframe(1.3, duration: 0.14, spring: .snappy)
                SpringKeyframe(1, duration: 0.4, spring: .bouncy(extraBounce: 0.2))
            }
            .onChange(of: count) { old, new in
                if new > old && !reduceMotion { bumps += 1 }
            }
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
        .buttonStyle(PuffSquishButtonStyle(haptic: false))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - 空状态

/// 空状态：咕咕或嘎嘎 + 标题 + 可选说明与操作。
public struct PuffEmptyState<Actions: View>: View {
    private let bird: PuffMascot.Bird
    private let pose: PuffMascot.Pose
    private let title: String
    private let message: String?
    private let actions: Actions
    @State private var hasAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        _ title: String,
        message: String? = nil,
        bird: PuffMascot.Bird = .gugu,
        pose: PuffMascot.Pose = .wave,
        @ViewBuilder actions: () -> Actions = { EmptyView() }
    ) {
        self.title = title
        self.message = message
        self.bird = bird
        self.pose = pose
        self.actions = actions()
    }

    public var body: some View {
        VStack(spacing: Puff.Space.s) {
            PuffMascot(bird, pose: pose, size: 124, reactsToTap: true)
                .scaleEffect(hasAppeared || reduceMotion ? 1 : 0.4, anchor: .bottom)
                .opacity(hasAppeared ? 1 : 0)
                .animation(Puff.Motion.resolve(Puff.Motion.pop, reduceMotion: reduceMotion), value: hasAppeared)
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
            .puffEntrance(index: 2, isShown: hasAppeared)
            actions
                .padding(.top, Puff.Space.xs)
                .puffEntrance(index: 4, isShown: hasAppeared)
        }
        .onAppear { hasAppeared = true }
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
    private let tapBurst: Bool
    private let caption: Caption

    /// - Parameter tapBurst: 点城市画面会迸出小星星。卡片本身是按钮时保持关闭。
    public init(
        regionID: String?,
        viewport: PuffCityScene.Viewport = .west,
        sceneHeight: CGFloat = 150,
        isActive: Bool = true,
        tapBurst: Bool = false,
        @ViewBuilder caption: () -> Caption
    ) {
        self.regionID = regionID
        self.viewport = viewport
        self.sceneHeight = sceneHeight
        self.isActive = isActive
        self.tapBurst = tapBurst
        self.caption = caption()
    }

    public var body: some View {
        VStack(spacing: 0) {
            PuffCityScene(regionID: regionID, viewport: viewport, isActive: isActive)
                .frame(height: sceneHeight)
                .clipShape(RoundedRectangle(cornerRadius: Puff.Radius.huge - 6, style: .continuous))
                .puffTapBurst(isEnabled: tapBurst)
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

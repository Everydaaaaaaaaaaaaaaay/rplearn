import BackendKit
import BillingKit
import CoreKit
import DesignSystem
import DomainKit
import PersistenceKit
import StoreKit
import SwiftUI

/// “我的”聚合页：资料、订阅、金币与二级入口。
public struct MyPageView: View {
    private let accessClient: BackendClient?
    private let economyStore: EconomyStore
    private let economyService: EconomyService
    private let rosterStore: RosterStore
    private let authSession: AuthSession
    private let billing: BillingController
    private let reloadToken: Int
    private let isSignedIn: Bool
    private let onSignIn: @MainActor () -> Void
    private let onCalibrateLevel: @MainActor () -> Void
    private let onOpenFavorites: @MainActor () -> Void
    private let onOpenSettings: @MainActor () -> Void
    private let onOpenMemory: @MainActor () -> Void

    @State private var pendingUsage = false
    @State private var pendingSignIn = false
    @State private var showsUsage = false
    @State private var profile: UserProfileDTO?
    @State private var occupiedFriendSlots = 0
    @State private var showsTierPicker = false
    @State private var showsManageSubscriptions = false
    @State private var showsAccountPanel = false
    @StateObject private var sceneActions = DSSceneActionCoordinator<MyPageSceneHotspot>()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var presentation: MyPagePresentation {
        MyPagePresentation(
            profile: profile,
            isSignedIn: isSignedIn,
            tier: billing.tier
        )
    }

    private var sceneLayout: TravelDeskSceneLayout {
        .production
    }

    public init(
        accessClient: BackendClient? = nil,
        economyStore: EconomyStore,
        economyService: EconomyService,
        rosterStore: RosterStore,
        authSession: AuthSession,
        billing: BillingController,
        reloadToken: Int = 0,
        isSignedIn: Bool,
        onSignIn: @escaping @MainActor () -> Void,
        onCalibrateLevel: @escaping @MainActor () -> Void,
        onOpenFavorites: @escaping @MainActor () -> Void,
        onOpenSettings: @escaping @MainActor () -> Void,
        onOpenMemory: @escaping @MainActor () -> Void = {}
    ) {
        self.accessClient = accessClient
        self.economyStore = economyStore
        self.economyService = economyService
        self.rosterStore = rosterStore
        self.authSession = authSession
        self.billing = billing
        self.reloadToken = reloadToken
        self.isSignedIn = isSignedIn
        self.onSignIn = onSignIn
        self.onCalibrateLevel = onCalibrateLevel
        self.onOpenFavorites = onOpenFavorites
        self.onOpenSettings = onOpenSettings
        self.onOpenMemory = onOpenMemory
    }

    public var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibleContent
            } else {
                modernTravelDesk
            }
        }
        .background(Color.dsBackground.ignoresSafeArea())
        .task(id: reloadToken) { await reload() }
        .onDisappear(perform: sceneActions.cancel)
        .sheet(isPresented: $showsAccountPanel, onDismiss: {
            if pendingUsage { pendingUsage = false; showsUsage = true }
            else if pendingSignIn { pendingSignIn = false; onSignIn() }
        }) {
            accountPanel
        }
        .sheet(isPresented: $showsUsage, onDismiss: {
            if pendingSignIn { pendingSignIn = false; onSignIn() }
        }) {
            if let accessClient {
                UsageAccessView(backend: accessClient, billing: billing) {
                    pendingSignIn = true
                    showsUsage = false
                }
            }
        }
        .manageSubscriptionsSheet(isPresented: $showsManageSubscriptions)
    }

    private var accessibleContent: some View {
        ScrollView {
            VStack(spacing: DSSpacing.md) {
                profileCard
                learningProfileCard
                subscriptionCard
                usageButton
                entryList
                #if DEBUG
                debugCard
                #endif
            }
            .padding(DSSpacing.md)
        }
        .refreshable { await reload() }
    }

    /// 现代旅行者工作台：背景只承载实物，全部入口由统一的实时全息组件绘制。
    private var modernTravelDesk: some View {
        GeometryReader { proxy in
            let widthScale = proxy.size.width / TravelDeskLayout.canvasWidth
            let heightScale = proxy.size.height / TravelDeskLayout.interactiveContentBottom
            let sceneScale = min(widthScale, heightScale)
            let horizontalInset = max(
                0,
                (proxy.size.width - TravelDeskLayout.canvasWidth * sceneScale) / 2
            )

            ZStack(alignment: .topLeading) {
                if sceneScale < widthScale {
                    compactHeightBackdrop(size: proxy.size)
                }

                travelDeskCanvas
                    .frame(
                        width: TravelDeskLayout.canvasWidth,
                        height: TravelDeskLayout.canvasHeight,
                        alignment: .topLeading
                    )
                    .dynamicTypeSize(...DynamicTypeSize.xLarge)
                    .scaleEffect(sceneScale, anchor: .topLeading)
                    .offset(x: horizontalInset)
            }
            .frame(
                width: proxy.size.width,
                height: proxy.size.height,
                alignment: .topLeading
            )
            .clipped()
        }
        .ignoresSafeArea(edges: [.top, .bottom])
        .dsSceneTabBarBackground()
    }

    /// 极短屏幕缩小参考画布后只会留下很窄的侧边余量；使用同源场景作柔化衬底，
    /// 避免硬色带，同时不参与任何入口的定位与点击。
    private func compactHeightBackdrop(size: CGSize) -> some View {
        MyPageCompactTravelDeskBackdrop(
            assetName: sceneLayout.assetName,
            size: size,
            overlayOpacity: colorScheme == .dark ? 0.3 : 0.035
        )
            .equatable()
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }

    /// 所有背景像素、入口、微光和点击区域都在同一参考画布中布局。
    /// 运行时只整体等比缩放画布，避免不同 iPhone 宽度下出现独立取整与锚点漂移。
    private var travelDeskCanvas: some View {
        let width = TravelDeskLayout.canvasWidth
        let sceneHeight = TravelDeskLayout.canvasHeight
        let layout = sceneLayout

        return ZStack(alignment: .topLeading) {
            travelDeskBackground(width: width, height: sceneHeight)

            profileHotspot
                .frame(width: layout.profile.size.width, height: layout.profile.size.height)
                .position(x: width * layout.profile.center.x, y: sceneHeight * layout.profile.center.y)

            coinHotspot
                .frame(width: layout.coin.size.width, height: layout.coin.size.height)
                .position(x: width * layout.coin.center.x, y: sceneHeight * layout.coin.center.y)

            learningHotspot
                .frame(width: layout.learning.size.width, height: layout.learning.size.height)
                .position(x: width * layout.learning.center.x, y: sceneHeight * layout.learning.center.y)

            favoritesHotspot
                .frame(width: layout.favorites.size.width, height: layout.favorites.size.height)
                .position(x: width * layout.favorites.center.x, y: sceneHeight * layout.favorites.center.y)

            settingsHotspot
                .frame(width: layout.settings.size.width, height: layout.settings.size.height)
                .position(x: width * layout.settings.center.x, y: sceneHeight * layout.settings.center.y)

            accountHotspot
                .frame(width: layout.account.size.width, height: layout.account.size.height)
                .position(x: width * layout.account.center.x, y: sceneHeight * layout.account.center.y)

            #if DEBUG
            memoryDebugHotspot
                .frame(width: layout.memory.size.width, height: layout.memory.size.height)
                .position(x: width * layout.memory.center.x, y: sceneHeight * layout.memory.center.y)
            #endif
        }
        .frame(width: width, height: sceneHeight, alignment: .topLeading)
    }

    private func travelDeskBackground(width: CGFloat, height: CGFloat) -> some View {
        MyPageTravelDeskBackground(
            assetName: sceneLayout.assetName,
            size: CGSize(width: width, height: height),
            overlayOpacity: colorScheme == .dark ? 0.28 : 0.02
        )
            .equatable()
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }

    private var profileHotspot: some View {
        Button {
            sceneActions.perform(for: .profile) {
                showsAccountPanel = true
            }
        } label: {
            profileSceneEntry
        }
        .buttonStyle(.myPageSceneEntrance(keepsPressedAppearance: sceneActions.pressedHotspot == .profile))
        .accessibilityLabel("个人资料，\(presentation.displayName)，\(presentation.accountBadgeTitle)，已认识 \(occupiedFriendSlots) 位旅途朋友")
        .accessibilityHint("查看账号、用量与权益")
    }

    private var coinHotspot: some View {
        coinLabel
    }

    private var coinLabel: some View {
        coinSceneEntry
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(profile?.coins ?? 0) 金币")
    }

    private var learningHotspot: some View {
        Button {
            sceneActions.perform(for: .learning, action: onCalibrateLevel)
        } label: {
            learningSceneEntry
        }
        .buttonStyle(.myPageSceneEntrance(keepsPressedAppearance: sceneActions.pressedHotspot == .learning))
        .accessibilityLabel("英语旅程，当前水平 \(profile?.difficultyLevel.displayName ?? "载入中")，学习目标 \(profile?.learningGoal.displayName ?? "载入中")")
        .accessibilityHint("重新校准英语水平")
    }

    private var favoritesHotspot: some View {
        Button {
            sceneActions.perform(for: .favorites, action: onOpenFavorites)
        } label: {
            fixedSceneEntry(
                glyph: .bookmarkStar,
                title: "收藏",
                plane: sceneLayout.favorites.plane,
                scale: sceneLayout.favorites.contentScale
            )
        }
        .buttonStyle(.myPageSceneEntrance(keepsPressedAppearance: sceneActions.pressedHotspot == .favorites))
        .accessibilityLabel("收藏夹，单词与语法点")
        .accessibilityHint("查看收藏的单词与语法点")
    }

    private var settingsHotspot: some View {
        Button {
            sceneActions.perform(for: .settings, action: onOpenSettings)
        } label: {
            fixedSceneEntry(
                glyph: .system("slider.horizontal.3"),
                title: "设置",
                plane: sceneLayout.settings.plane,
                scale: sceneLayout.settings.contentScale
            )
        }
        .buttonStyle(.myPageSceneEntrance(keepsPressedAppearance: sceneActions.pressedHotspot == .settings))
        .accessibilityLabel("设置，AI、语音与偏好")
        .accessibilityHint("打开设置")
    }

    private var accountHotspot: some View {
        Button {
            sceneActions.perform(for: .account) {
                if isSignedIn {
                    showsAccountPanel = true
                } else {
                    onSignIn()
                }
            }
        } label: {
            fixedSceneEntry(
                glyph: .account,
                title: "登录",
                plane: sceneLayout.account.plane,
                scale: sceneLayout.account.contentScale
            )
        }
        .buttonStyle(.myPageSceneEntrance(keepsPressedAppearance: sceneActions.pressedHotspot == .account))
        .accessibilityLabel(isSignedIn ? "账号与订阅" : "登录或创建账号")
        .accessibilityHint(isSignedIn ? "同步旅程与管理方案" : "跨设备同步与订阅恢复")
    }

    #if DEBUG
    private var memoryDebugHotspot: some View {
        Button {
            sceneActions.perform(for: .memory, action: onOpenMemory)
        } label: {
            fixedSceneEntry(
                glyph: .system("photo"),
                title: "记忆",
                plane: sceneLayout.memory.plane,
                scale: sceneLayout.memory.contentScale
            )
        }
        .buttonStyle(.myPageSceneEntrance(keepsPressedAppearance: sceneActions.pressedHotspot == .memory))
        .accessibilityLabel("记忆调试面板")
        .accessibilityHint("查看角色长期与近期记忆")
    }
    #endif

    private var profileSceneEntry: some View {
        let scale = sceneLayout.profile.contentScale

        return MyPageProfileSceneEntry(
            plane: sceneLayout.profile.plane,
            scale: scale,
            displayName: presentation.displayName,
            accountBadgeTitle: presentation.accountBadgeTitle,
            occupiedFriendSlots: occupiedFriendSlots
        )
    }

    private var coinSceneEntry: some View {
        fixedSceneEntry(
            glyph: .coinStacks,
            title: "\(profile?.coins ?? 0) 金币",
            plane: sceneLayout.coin.plane,
            tint: .sceneHologramYellow,
            scale: sceneLayout.coin.contentScale
        )
    }

    private var learningSceneEntry: some View {
        let scale = sceneLayout.learning.contentScale

        return SceneHologram(plane: sceneLayout.learning.plane) {
            VStack(spacing: 7 * scale) {
                SceneHologramIcon(glyph: .journeyBook, size: 44 * scale)
                SceneHologramText("英语旅程", size: 20 * scale, weight: .bold)
                SceneHologramText(
                    "\(profile?.difficultyLevel.displayName ?? "载入中") · \(profile?.learningGoal.displayName ?? "载入中")",
                    size: 11.25 * scale,
                    weight: .semibold
                )
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .padding(.horizontal, 8)
                SceneHologramText(presentation.placementSummary, size: 11.5 * scale, weight: .bold)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    private func fixedSceneEntry(
        glyph: SceneHologramGlyph,
        title: String,
        plane: SceneHologramPlane,
        tint: Color = .sceneHologramYellow,
        scale: CGFloat
    ) -> some View {
        SceneHologram(plane: plane, tint: tint) {
            VStack(spacing: 6 * scale) {
                SceneHologramIcon(glyph: glyph, size: 48 * scale, tint: tint)
                SceneHologramText(title, size: 24 * scale, weight: .bold, tint: tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    private var accountPanel: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DSSpacing.md) {
                    profileCard
                    subscriptionCard
                    usageButton
                    if isSignedIn {
                        Button(role: .destructive) {
                            Task {
                                await authSession.logout()
                                showsAccountPanel = false
                            }
                        } label: {
                            Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.dsAction(.secondary, fullWidth: true))
                    }
                }
                .padding(DSSpacing.md)
            }
            .background(Color.dsBackground)
            .navigationTitle("账号与版本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { showsAccountPanel = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var profileCard: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    HStack(spacing: DSSpacing.sm) {
                        AvatarBadge(name: presentation.displayName, tint: .dsSky, size: 60)
                        Text(presentation.displayName)
                            .font(.title2.bold())
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    DSChip(
                        presentation.accountBadgeTitle,
                        tint: presentation.accountBadgeTint,
                        prominent: isSignedIn && billing.tier != .free
                    )
                    Label("已认识 \(occupiedFriendSlots) 位旅途朋友", systemImage: "person.2.fill")
                        .foregroundStyle(.secondary)
                    Label("\(profile?.coins ?? 0) 金币", systemImage: "circle.grid.2x1.fill")
                        .foregroundStyle(Color.dsSunset)
                        .monospacedDigit()
                }
            } else {
                HStack(spacing: DSSpacing.md) {
                    AvatarBadge(name: presentation.displayName, tint: .dsSky, size: 68)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(presentation.displayName)
                            .font(.title2.bold())
                        DSChip(
                            presentation.accountBadgeTitle,
                            tint: presentation.accountBadgeTint,
                            prominent: isSignedIn && billing.tier != .free
                        )
                        Text("已认识 \(occupiedFriendSlots) 位旅途朋友")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "circle.grid.2x1.fill")
                            .foregroundStyle(Color.dsSunset)
                        Text("\(profile?.coins ?? 0)")
                            .font(.title3.bold().monospacedDigit())
                        Text("金币")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .dsSurface(.elevated)
    }

    private var usageButton: some View {
        Button {
            if showsAccountPanel { pendingUsage = true; showsAccountPanel = false }
            else { showsUsage = true }
        } label: { Label("用量与权益", systemImage: "chart.bar.fill") }
    }

    private var subscriptionCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            if isSignedIn {
                subscriptionHeader

                HStack {
                    Button {
                        withAnimation(reduceMotion ? nil : DSAnimation.snappy) {
                            showsTierPicker.toggle()
                        }
                    } label: {
                        Label(showsTierPicker ? "收起方案" : "查看订阅方案", systemImage: "sparkles")
                    }
                    .buttonStyle(.dsAction(.glass, fullWidth: false, compact: true))
                    .tint(.white)

                    if billing.tier != .free {
                        Button("管理") {
                            showsManageSubscriptions = true
                        }
                        .buttonStyle(.dsAction(.glass, fullWidth: false, compact: true))
                        .tint(.white)
                    }
                }

                if showsTierPicker {
                    VStack(spacing: DSSpacing.xs) {
                        if billing.operation == .loading {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                        } else if billing.offeredProducts.isEmpty {
                            Text("当前 App Store 账户暂无可购买方案。")
                                .font(.footnote)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ForEach(billing.offeredProducts) { product in
                                Button {
                                    Task {
                                        await billing.purchase(product)
                                        await reload()
                                    }
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(product.tier.displayName)
                                                .fontWeight(.bold)
                                            if let period = product.periodDescription {
                                                Text(period)
                                                    .font(.caption)
                                                    .opacity(0.76)
                                            }
                                        }
                                        Spacer()
                                        Text(product.displayPrice)
                                            .fontWeight(.bold)
                                            .monospacedDigit()
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.dsAction(.glass, fullWidth: true, compact: true))
                                .tint(.white)
                                .disabled(billing.operation != .idle)
                            }
                        }

                        Button("恢复购买") {
                            Task {
                                await billing.restorePurchases()
                                await reload()
                            }
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .disabled(billing.operation != .idle)
                    }
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }

                if let validity = billing.currentValidityDescription {
                    Text(validity)
                        .font(.caption2)
                        .opacity(0.76)
                }
                if let message = billing.message {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                }
                if let error = billing.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                }
            } else {
                guestAccountPrompt
            }
        }
        .foregroundStyle(.white)
        .padding(DSSpacing.md)
        .background(
            LinearGradient(
                colors: [Color.dsSkyDeep, Color.dsSky, Color.dsCyan],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: DSRadius.hero, style: .continuous)
        )
        .shadow(color: Color.dsSky.opacity(0.24), radius: 12, y: 5)
    }

    private var learningProfileCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("英语学习档案")
                        .font(.headline)
                    Text(
                        profile?.proficiencySource == .placement
                            ? "已通过答题校准"
                            : "当前使用自选水平"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button("校准水平", action: onCalibrateLevel)
                    .buttonStyle(.dsAction(.secondary, fullWidth: false, compact: true))
            }

            HStack(spacing: DSSpacing.sm) {
                learningMetric(
                    title: "当前水平",
                    value: profile?.difficultyLevel.displayName ?? "载入中",
                    icon: "gauge.with.dots.needle.33percent"
                )
                learningMetric(
                    title: "学习目标",
                    value: profile?.learningGoal.displayName ?? "载入中",
                    icon: "scope"
                )
            }

            if let score = profile?.placementScore {
                HStack {
                    Label("最近校准 \(score) / 100", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(Color.dsSkyDeep)
                    Spacer()
                    if let date = profile?.placementCompletedAt {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption.weight(.semibold))
            }
        }
        .dsSurface(.grouped)
    }

    private func learningMetric(
        title: String,
        value: String,
        icon: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DSSpacing.sm)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(Color.dsSurfaceMuted, in: RoundedRectangle(cornerRadius: DSRadius.inline))
    }

    private var guestAccountPrompt: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("游客体验")
                        .font(.title3.bold())
                    Text("3 个普通好友位，体验起始城市与剧情首站")
                        .font(.footnote)
                        .opacity(0.86)
                }
                Spacer()
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.largeTitle)
            }

            Button {
                if showsAccountPanel { pendingSignIn = true; showsAccountPanel = false }
                else { onSignIn() }
            } label: {
                Label("登录或创建账号", systemImage: "icloud.and.arrow.up")
            }
            .buttonStyle(.dsAction(.glass, fullWidth: false, compact: true))
            .tint(.white)

            Text("游客额度为一次性体验。登录后获得 5 个普通好友位和每日额度，并可继续剧情、飞往其他城市。剧情旅伴不占好友位。")
                .font(.caption2)
                .opacity(0.76)
        }
    }

    @ViewBuilder
    private var subscriptionHeader: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.title)
                Text("\(AppBrand.englishName) \(billing.tier.displayName)")
                    .font(.headline.bold())
                Text("更长的角色记忆，让每段友谊都有延续")
                    .font(.body)
                    .opacity(0.86)
            }
        } else {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(AppBrand.englishName) \(billing.tier.displayName)")
                        .font(.title3.bold())
                    Text("更长的角色记忆，让每段友谊都有延续")
                        .font(.footnote)
                        .opacity(0.86)
                }
                Spacer()
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.largeTitle)
            }
        }
    }

    private var entryList: some View {
        VStack(spacing: 0) {
            Button(action: onOpenFavorites) {
                MyPageEntryRow("收藏夹", subtitle: "收集旅途中遇到的单词与语法点", icon: "star.fill", tint: .dsSunset)
            }
            .buttonStyle(.plain)
            Divider().padding(.leading, 56)
            Button(action: onOpenSettings) {
                MyPageEntryRow("设置", subtitle: "AI、语音与学习偏好", icon: "gearshape.fill", tint: .dsSky)
            }
            .buttonStyle(.plain)
            Divider().padding(.leading, 56)
            if isSignedIn {
                Button(role: .destructive) {
                    Task { await authSession.logout() }
                } label: {
                    MyPageEntryRow(
                        "退出登录",
                        subtitle: "退出账号并回到本地游客空间",
                        icon: "rectangle.portrait.and.arrow.right",
                        tint: .red
                    )
                }
                .buttonStyle(.plain)
            } else {
                Button(action: onSignIn) {
                    MyPageEntryRow(
                        "登录或创建账号",
                        subtitle: "用于跨设备同步与订阅恢复",
                        icon: "person.crop.circle.badge.plus",
                        tint: .dsSky
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .dsSurface(.grouped, padding: 0)
    }

    #if DEBUG
    private var debugCard: some View {
        VStack(spacing: 0) {
            Button(action: onOpenMemory) {
                MyPageEntryRow("记忆调试面板", subtitle: "查看角色长期与近期记忆", icon: "brain.head.profile", tint: .dsQuiz)
            }
            .buttonStyle(.plain)
        }
        .dsSurface(.grouped, padding: 0)
    }
    #endif

    private func reload() async {
        async let loadedProfile = try? economyStore.profile()
        async let loadedSlots = try? rosterStore.occupiedFriendSlots()
        profile = await loadedProfile
        occupiedFriendSlots = await loadedSlots ?? 0
    }
}
